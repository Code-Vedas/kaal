# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'fugit'
require_relative 'enabled_entry_enumerator'
require_relative 'occurrence_finder'
require 'kaal/config/scheduler_time_zone_resolver'

module Kaal
  ##
  # Coordinator manages the main scheduler loop that calculates due fire times
  # and dispatches cron work safely across multiple nodes using backend lease coordination.
  #
  # The coordinator:
  # 1. Runs a background thread on tick_interval
  # 2. For each registered cron, calculates due fire times within the window
  # 3. Attempts to acquire a distributed lease for each due time
  # 4. Calls the enqueue callback if the lease is acquired
  # 5. Supports graceful shutdown and re-entrancy for testing
  #
  # @example Start the coordinator
  #   coordinator = Kaal::Coordinator.new
  #   coordinator.start!
  #
  # @example Manual tick execution (for testing)
  #   coordinator.tick!
  #
  # @example Stop the coordinator
  #   coordinator.stop!
  class Coordinator
    DELAYED_JOB_BATCH_SIZE = 100
    DELAYED_JOB_DELETE_CONFIRMATION_JITTER_MAX = 0.05

    ##
    # Initialize a new Coordinator instance.
    #
    # @param configuration [Configuration] the scheduler configuration
    # @param registry [Registry] the registered crons registry
    def initialize(configuration:, registry:)
      @configuration = configuration
      @registry = registry
      @thread = nil
      @running = false
      @stop_requested = false
      @mutex = Mutex.new
      @tick_cv = ConditionVariable.new
    end

    ##
    # Start the coordinator background thread.
    #
    # @return [Thread] the started thread, or nil if already running
    # @safe
    def start!
      @mutex.synchronize do
        return nil if @running

        # Run recovery before starting the main loop
        recover_missed_runs

        @running = true
        @stop_requested = false
        @thread = Thread.new { run_loop }
        @thread.abort_on_exception = true
        return @thread
      end
    end

    ##
    # Stop the coordinator gracefully.
    #
    # Signals the coordinator to stop after the current tick completes,
    # then waits for the thread to finish.
    #
    # @param timeout [Integer] seconds to wait for graceful shutdown (default: 30)
    # @return [Boolean] true if stopped, false if timeout
    # @safe
    def stop!(timeout: 30) # rubocop:disable Naming/PredicateMethod
      request_stop

      # Wait for thread to finish outside the lock
      result = @thread&.join(timeout)

      # If we had a thread and join timed out, thread is still alive
      return false if @thread && result.nil?

      @thread = nil
      @mutex.synchronize { @running = false }

      true
    end

    ##
    # Check if the coordinator is currently running.
    #
    # @return [Boolean] true if running, false otherwise
    def running?
      @mutex.synchronize { @running }
    end

    ##
    # Restart the coordinator (stop then start).
    #
    # @return [Thread] the started thread
    # @safe
    def restart!
      stop!
      start!
    end

    ##
    # Execute a single tick manually.
    #
    # This is useful for testing and Rake tasks that want to trigger
    # the scheduler without running the background loop.
    #
    # @return [void]
    # @safe
    def tick!
      execute_tick
    end

    ##
    # Reset coordinator state for re-entrancy in tests.
    #
    # Stops any running thread before clearing state to avoid orphaning it.
    # Raises an error if the thread cannot be stopped within the timeout.
    #
    # @return [void]
    # @raise [RuntimeError] if stop! times out
    # @safe
    def reset!
      # Stop any running thread first to prevent orphaned threads
      if running?
        stopped = stop!
        raise 'Failed to stop coordinator thread within timeout' unless stopped
      end

      # Now safe to reset all state
      @mutex.synchronize do
        @running = false
        @stop_requested = false
        @thread = nil
      end
    end

    private

    def request_stop
      @mutex.synchronize do
        return unless @running

        @stop_requested = true
        @tick_cv.signal
      end
    end

    def run_loop
      loop do
        break if stop_requested?

        execute_tick
        sleep_until_next_tick
      end
    ensure
      @mutex.synchronize { @running = false }
    end

    def stop_requested?
      @mutex.synchronize { @stop_requested }
    end

    def execute_tick
      each_enabled_entry do |entry|
        calculate_and_dispatch_due_times(entry)
      end
      dispatch_due_delayed_jobs
    rescue ConfigurationError => e
      log_configuration_error('Kaal coordinator tick failed', e)
      raise
    rescue StandardError => e
      log_runtime_error('Kaal coordinator tick failed', e)
    end

    def calculate_and_dispatch_due_times(entry)
      now = Time.now.utc
      window_start = now - @configuration.window_lookback
      window_end = now + @configuration.window_lookahead

      # Parse cron expression using fugit
      cron = parse_cron(entry.cron)
      return unless cron

      # Find all occurrences within the window
      occurrences = find_occurrences(cron, window_start, window_end)
      @configuration.logger&.debug("Coordinator: Found #{occurrences.length} occurrences for #{entry.key} in window [#{window_start}, #{window_end}]")

      # For each occurrence that's due (in the past or now), try to dispatch
      occurrences.each do |fire_time|
        dispatch_if_due(entry, fire_time, now)
      end
    end

    def parse_cron(cron_expression)
      result = Fugit.parse_cron("#{cron_expression} #{scheduler_time_zone_resolver.time_zone_identifier}")
      raise ArgumentError, "Invalid cron expression: #{cron_expression}" unless result

      result
    rescue ArgumentError => e
      @configuration.logger&.warn("Failed to parse cron expression '#{cron_expression}': #{e.message}")
      nil
    end

    def find_occurrences(cron, start_time, end_time)
      occurrence_finder.call(cron:, start_time:, end_time:)
    end

    def dispatch_if_due(entry, fire_time, now)
      # Only dispatch if fire_time is in the past or now
      return if fire_time > now

      logger = @configuration.logger
      cron_key = entry.key
      return if Kaal.configuration.enable_log_dispatch_registry && already_dispatched?(cron_key, fire_time)

      # Generate a unique backend coordination key for this fire time
      lock_key = generate_lock_key(cron_key, fire_time)

      # Try to acquire the coordination lease
      if acquire_lock(lock_key)
        dispatch_work(entry, fire_time)
      elsif logger
        logger.debug("Failed to acquire lock for #{lock_key}")
      end
    rescue StandardError => e
      cron_key ||= 'unknown'
      logger&.error("Error dispatching work for #{cron_key}: #{e.message}")
    end

    ##
    # Recover missed cron runs after downtime.
    #
    # Looks back over the recovery window to find cron jobs that should have executed
    # but were missed due to downtime. Uses dispatch records (if enabled) to skip
    # already-dispatched jobs, and relies on lease coordination for duplicate prevention.
    #
    # @return [void]
    def recover_missed_runs
      return unless @configuration.enable_dispatch_recovery

      # Add random jitter to reduce lock contention when multiple nodes restart simultaneously
      jitter = rand(0..@configuration.recovery_startup_jitter)
      sleep(jitter) if jitter.positive?

      current_time = Time.now.utc
      recovery_window = @configuration.recovery_window
      recovery_start = current_time - recovery_window
      recovery_end = current_time

      logger = @configuration.logger
      logger&.info("Starting missed-run recovery for window: #{recovery_start} to #{recovery_end}")

      total_recovered = 0
      each_enabled_entry do |entry|
        recovered = recover_entry(entry, recovery_start, recovery_end)
        total_recovered += recovered
      end

      logger&.info("Missed-run recovery completed: attempted #{total_recovered} dispatches")

      # Clean up old dispatch records after recovery completes
      cleanup_old_dispatch_records(recovery_window)
    rescue ConfigurationError => e
      log_configuration_error('Kaal missed-run recovery failed', e, logger:)
      raise
    rescue StandardError => e
      log_runtime_error('Error during missed-run recovery', e, logger:)
    end

    ##
    # Recover missed runs for a single cron entry.
    #
    # @param entry [Kaal::Registry::Entry] the cron job entry
    # @param start_time [Time] the start of the recovery window
    # @param end_time [Time] the end of the recovery window
    # @return [Integer] number of occurrences attempted to dispatch
    def recover_entry(entry, start_time, end_time)
      logger = @configuration.logger
      entry_key = entry.key
      cron = parse_cron(entry.cron)
      return 0 unless cron

      occurrences = find_occurrences(cron, start_time, end_time)

      # Filter out already-dispatched runs if dispatch logging is enabled
      occurrences.reject! { |fire_time| already_dispatched?(entry_key, fire_time) } if @configuration.enable_log_dispatch_registry
      occurrences_size = occurrences.size
      logger&.info("Recovering #{occurrences_size} missed runs for #{entry_key}")

      # Attempt to dispatch each missed occurrence
      occurrences.each do |fire_time|
        dispatch_if_due(entry, fire_time, Time.now.utc)
      end

      occurrences_size
    rescue ConfigurationError => e
      log_configuration_error("Error recovering entry #{entry_key}", e, logger:)
      raise
    rescue StandardError => e
      log_runtime_error("Error recovering entry #{entry_key}", e, logger:)
      0
    end

    ##
    # Clean up old dispatch records to prevent database bloat.
    #
    # Called after recovery completes. Deletes dispatch records older than
    # the recovery window, since they are no longer needed for future recovery.
    #
    # @param recovery_window [Integer] seconds - records older than this are deleted
    # @return [void]
    def cleanup_old_dispatch_records(recovery_window)
      logger = @configuration.logger
      adapter = @configuration.backend
      return if adapter.nil? || !adapter.respond_to?(:dispatch_registry)

      registry = adapter.dispatch_registry
      return unless registry.respond_to?(:cleanup)

      deleted_count = registry.cleanup(recovery_window: recovery_window)
      logger&.debug("Cleaned up #{deleted_count} old dispatch records") if deleted_count.positive?
    rescue StandardError => e
      logger&.warn("Error cleaning up old dispatch records: #{e.message}")
    end

    ##
    # Check if a cron job was already dispatched.
    #
    # @param key [String] the cron job key
    # @param fire_time [Time] the fire time to check
    # @return [Boolean] true if already dispatched, false otherwise
    def already_dispatched?(key, fire_time)
      adapter = @configuration.backend
      return false if adapter.nil? || !adapter.respond_to?(:dispatch_registry)

      adapter.dispatch_registry.dispatched?(key, fire_time)
    rescue StandardError => e
      @configuration.logger&.warn("Error checking dispatch status for #{key}: #{e.message}")
      false
    end

    def acquire_lock(lock_key)
      backend = @configuration.backend
      logger = @configuration.logger

      # No adapter = no locking (dev/test)
      return true unless backend

      backend.acquire(lock_key, @configuration.lease_ttl)
    rescue StandardError => e
      logger&.error("Lock acquisition failed for #{lock_key}: #{e.message}")
      false
    end

    def each_enabled_entry(&)
      enabled_entry_enumerator.each(&)
    end

    def dispatch_work(entry, fire_time)
      # Call the enqueue callback with fire_time and idempotency_key
      cron_key = entry.key
      logger = @configuration.logger

      idempotency_key = generate_idempotency_key(cron_key, fire_time)
      entry.enqueue.call(fire_time:, idempotency_key:)
      logger&.debug("Dispatched work for #{cron_key} at #{fire_time}")
    rescue StandardError => e
      logger&.error("Work dispatch failed for #{cron_key}: #{e.message}")
    end

    def dispatch_due_delayed_jobs
      delayed_store = delayed_store_for_tick
      return unless delayed_store

      loop do
        apply_delayed_job_claim_jitter_if_needed(delayed_store)
        due_jobs = delayed_store.pop_due(now: Time.now.utc, limit: DELAYED_JOB_BATCH_SIZE)
        break if due_jobs.empty?

        due_jobs.each do |job|
          dispatch_delayed_job(job, delayed_store)
        end
      end
    rescue StandardError => e
      @configuration.logger&.error("Delayed job dispatch failed: #{e.message}")
    end

    def dispatch_delayed_job(job, delayed_store)
      if delayed_store.requires_dispatch_lock?
        lock_key = generate_delayed_lock_key(job.fetch(:job_id))
        return unless acquire_lock(lock_key)
      end

      job_class = Kaal::JobDispatcher.resolve_job_class(
        job_class_name: job.fetch(:job_class),
        key: job.fetch(:job_id),
        queue: job[:queue]
      )
      Kaal::JobDispatcher.dispatch(job_class:, queue: job[:queue], args: job.fetch(:args))
      @configuration.logger&.debug("Dispatched delayed job #{job.fetch(:job_id)} for #{job.fetch(:run_at)}")
      true
    rescue StandardError => e
      Kaal::DelayedJob::DispatchFailureLogger.log_claimed_dispatch_failure(
        logger: @configuration.logger,
        job:,
        error: e
      )
      nil
    end

    def delayed_store_for_tick
      backend = @configuration.backend
      backend.respond_to?(:delayed_store) ? backend.delayed_store : nil
    end

    def apply_delayed_job_claim_jitter_if_needed(delayed_store)
      return unless delayed_store.claim_strategy == :delete_confirmation

      jitter = rand * DELAYED_JOB_DELETE_CONFIRMATION_JITTER_MAX
      sleep(jitter) if jitter.positive?
    end

    def generate_idempotency_key(cron_key, fire_time) = Kaal::IdempotencyKeyGenerator.call(cron_key, fire_time, configuration: @configuration)

    def generate_lock_key(cron_key, fire_time) = "#{@configuration.namespace || 'kaal'}:dispatch:#{cron_key}:#{fire_time.to_i}"

    def generate_delayed_lock_key(job_id) = "#{@configuration.namespace || 'kaal'}:delayed_dispatch:#{job_id}"

    def sleep_until_next_tick
      @mutex.synchronize do
        @tick_cv.wait(@mutex, @configuration.tick_interval)
      end
    rescue StandardError => e
      @configuration.logger&.error("Sleep interrupted: #{e.message}")
    end

    def scheduler_time_zone_resolver
      @scheduler_time_zone_resolver ||= SchedulerTimeZoneResolver.new(configuration: @configuration)
    end

    def occurrence_finder
      @occurrence_finder ||= OccurrenceFinder.new(configuration: @configuration)
    end

    def enabled_entry_enumerator
      @enabled_entry_enumerator ||= EnabledEntryEnumerator.new(configuration: @configuration, registry: @registry)
    end

    def log_configuration_error(prefix, error, logger: @configuration.logger)
      logger&.error("#{prefix} due to configuration error: #{error.message}")
    end

    def log_runtime_error(prefix, error, logger: @configuration.logger)
      logger&.error("#{prefix}: #{error.message}")
    end
  end
end
