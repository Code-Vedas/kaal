# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'

RSpec.describe Kaal::OccurrenceFinder do
  let(:logger_io) { StringIO.new }
  let(:configuration) { Kaal::Configuration.new.tap { |config| config.logger = Logger.new(logger_io) } }
  let(:finder) { described_class.new(configuration: configuration) }

  it 'collects occurrences inside the time window' do
    cron = Fugit.parse_cron('*/5 * * * *')
    start_time = Time.utc(2026, 1, 1, 0, 0, 0)
    end_time = Time.utc(2026, 1, 1, 0, 10, 0)

    expect(finder.call(cron:, start_time:, end_time:)).to eq(
      [Time.utc(2026, 1, 1, 0, 5, 0), Time.utc(2026, 1, 1, 0, 10, 0)]
    )
  end

  it 'returns an empty array when cron calculation fails' do
    broken_cron = Object.new
    broken_cron.define_singleton_method(:next_time) { |_current_time| raise StandardError, 'boom' }

    expect(
      finder.call(cron: broken_cron, start_time: Time.utc(2026, 1, 1), end_time: Time.utc(2026, 1, 1, 0, 10))
    ).to eq([])
    expect(logger_io.string).to include('Failed to calculate occurrences')
  end

  it 'covers nil-logger, nil-occurrence, and out-of-range occurrence branches' do
    configuration.logger = nil

    nil_cron = Object.new
    nil_cron.define_singleton_method(:next_time) { |_current_time| nil }
    expect(
      finder.call(cron: nil_cron, start_time: Time.utc(2026, 1, 1), end_time: Time.utc(2026, 1, 1, 0, 10))
    ).to eq([])

    late_cron = Object.new
    late_cron.define_singleton_method(:next_time) { |_current_time| Time.utc(2026, 1, 1, 0, 11) }
    expect(
      finder.call(cron: late_cron, start_time: Time.utc(2026, 1, 1), end_time: Time.utc(2026, 1, 1, 0, 10))
    ).to eq([])

    broken_cron = Object.new
    broken_cron.define_singleton_method(:next_time) { |_current_time| raise StandardError, 'boom' }
    expect(
      finder.call(cron: broken_cron, start_time: Time.utc(2026, 1, 1), end_time: Time.utc(2026, 1, 1, 0, 10))
    ).to eq([])
  end

  describe Kaal::EnabledEntryEnumerator do
    let(:logger_io) { StringIO.new }
    let(:configuration) { Kaal::Configuration.new.tap { |config| config.logger = Logger.new(logger_io) } }
    let(:registry) { Kaal::Registry.new }
    let(:callback) { ->(**) {} }

    before do
      registry.add(key: 'job:a', cron: '* * * * *', enqueue: callback)
    end

    it 'falls back to registry entries when there is no definition registry' do
      enumerator = described_class.new(configuration:, registry:, definition_registry_provider: -> {})

      expect(enumerator.each.to_a.map(&:key)).to eq(['job:a'])
    end

    it 'uses enabled persisted definitions when available' do
      definition_registry = Kaal::Definition::MemoryEngine.new
      definition_registry.upsert_definition(key: 'job:a', cron: '*/5 * * * *', enabled: true, source: 'code', metadata: {})
      definition_registry.upsert_definition(key: 'job:b', cron: '* * * * *', enabled: true, source: 'code', metadata: {})

      enumerator = described_class.new(configuration:, registry:, definition_registry_provider: -> { definition_registry })

      expect(enumerator.each.to_a.map(&:key)).to eq(['job:a'])
      expect(logger_io.string).to include("No enqueue callback registered for definition 'job:b'")
    end

    it 'falls back to registry entries when provider raises' do
      enumerator = described_class.new(configuration:, registry:, definition_registry_provider: -> { raise 'boom' })

      expect(enumerator.each.to_a.map(&:key)).to eq(['job:a'])
      expect(logger_io.string).to include('Failed to iterate enabled definitions')
    end

    it 'covers nil-logger branches for provider failures and missing callbacks' do
      configuration.logger = nil
      enumerator = described_class.new(configuration:, registry:, definition_registry_provider: -> { raise 'boom' })
      expect(enumerator.each.to_a.map(&:key)).to eq(['job:a'])

      empty_registry = Kaal::Registry.new
      definition_registry = Kaal::Definition::MemoryEngine.new
      definition_registry.upsert_definition(key: 'job:a', cron: '* * * * *', enabled: true, source: 'code', metadata: {})
      enumerator = described_class.new(configuration:, registry: empty_registry, definition_registry_provider: -> { definition_registry })
      expect(enumerator.each.to_a).to eq([])
    end
  end

  describe Kaal::Coordinator do
    let(:logger_io) { StringIO.new }
    let(:backend) { Kaal::Backend::MemoryAdapter.new }
    let(:configuration) do
      Kaal::Configuration.new.tap do |config|
        config.logger = Logger.new(logger_io)
        config.backend = backend
        config.enable_dispatch_recovery = false
        config.tick_interval = 0.01
        config.lease_ttl = 30
        config.namespace = 'ops'
      end
    end
    let(:registry) { Kaal::Registry.new }
    let(:coordinator) { described_class.new(configuration:, registry:) }
    let(:entry) { Kaal::Registry::Entry.new(key: 'job:a', cron: '*/5 * * * *', enqueue: ->(**) {}).freeze }

    it 'starts once and stops cleanly' do
      allow(coordinator).to receive(:recover_missed_runs)
      allow(coordinator).to receive(:run_loop)

      thread = coordinator.start!
      expect(thread).to be_a(Thread)
      expect(coordinator.start!).to be_nil
      expect(coordinator.stop!).to be(true)
    end

    it 'returns false when stop times out and reset raises on failed stop' do
      thread = instance_double(Thread, join: nil)
      coordinator.instance_variable_set(:@thread, thread)
      coordinator.instance_variable_set(:@running, true)

      expect(coordinator.stop!).to be(false)

      allow(coordinator).to receive_messages(running?: true, stop!: false)
      expect { coordinator.reset! }.to raise_error(RuntimeError, /Failed to stop coordinator thread/)
    end

    it 'executes ticks and rescues runtime errors' do
      allow(coordinator).to receive(:each_enabled_entry).and_yield(entry)
      allow(coordinator).to receive(:calculate_and_dispatch_due_times)

      coordinator.tick!
      expect(coordinator).to have_received(:calculate_and_dispatch_due_times).with(entry)

      allow(coordinator).to receive(:each_enabled_entry).and_raise(StandardError, 'boom')
      coordinator.send(:execute_tick)
      expect(logger_io.string).to include('Kaal coordinator tick failed: boom')
    end

    it 're-raises configuration errors during tick execution' do
      allow(coordinator).to receive(:each_enabled_entry).and_raise(Kaal::ConfigurationError, 'bad config')

      expect { coordinator.send(:execute_tick) }.to raise_error(Kaal::ConfigurationError, 'bad config')
      expect(logger_io.string).to include('Kaal coordinator tick failed due to configuration error')
    end

    it 'parses valid crons and rejects invalid ones' do
      expect(coordinator.send(:parse_cron, '*/5 * * * *')).to be_a(Fugit::Cron)
      expect(coordinator.send(:parse_cron, 'bad cron')).to be_nil
      expect(logger_io.string).to include('Failed to parse cron expression')
    end

    it 'dispatches due work and skips future work' do
      allow(coordinator).to receive(:acquire_lock).and_return(true)
      allow(coordinator).to receive(:dispatch_work)
      now = Time.utc(2026, 1, 1, 0, 0, 0)

      coordinator.send(:dispatch_if_due, entry, now + 60, now)
      expect(coordinator).not_to have_received(:dispatch_work)

      coordinator.send(:dispatch_if_due, entry, now, now)
      expect(coordinator).to have_received(:dispatch_work).with(entry, now)
    end

    it 'skips due work that was already dispatched when dispatch logging is enabled' do
      configuration.enable_log_dispatch_registry = true
      Kaal.configuration.enable_log_dispatch_registry = true
      now = Time.utc(2026, 1, 1, 0, 0, 0)

      allow(coordinator).to receive(:already_dispatched?).with(entry.key, now).and_return(true)
      allow(coordinator).to receive(:acquire_lock)
      allow(coordinator).to receive(:dispatch_work)

      coordinator.send(:dispatch_if_due, entry, now, now)

      expect(coordinator).not_to have_received(:acquire_lock)
      expect(coordinator).not_to have_received(:dispatch_work)
    end

    it 'logs failed lock acquisition and dispatch exceptions' do
      allow(coordinator).to receive(:acquire_lock).and_return(false)
      now = Time.utc(2026, 1, 1, 0, 0, 0)
      coordinator.send(:dispatch_if_due, entry, now, now)
      expect(logger_io.string).to include('Failed to acquire lock')

      allow(coordinator).to receive(:acquire_lock).and_raise(StandardError, 'boom')
      coordinator.send(:dispatch_if_due, entry, now, now)
      expect(logger_io.string).to include('Error dispatching work for')
    end

    it 'recovers missed runs and cleans up old dispatch records' do
      registry.add(key: 'job:a', cron: '*/5 * * * *', enqueue: ->(**) {})
      configuration.enable_dispatch_recovery = true
      configuration.enable_log_dispatch_registry = true
      dispatch_registry = Class.new do
        attr_reader :cleanup_calls

        def initialize
          @cleanup_calls = 0
        end

        def dispatched?(*)
          false
        end

        def cleanup(*)
          @cleanup_calls += 1
          2
        end
      end.new
      allow(backend).to receive(:dispatch_registry).and_return(dispatch_registry)
      allow(coordinator).to receive(:each_enabled_entry).and_yield(entry)
      allow(coordinator).to receive(:dispatch_if_due)
      allow(coordinator).to receive(:sleep)
      allow(coordinator).to receive_messages(parse_cron: Fugit.parse_cron('*/5 * * * *'), find_occurrences: [Time.utc(2026, 1, 1, 0, 0, 0)], rand: 0)

      coordinator.send(:recover_missed_runs)

      expect(coordinator).to have_received(:dispatch_if_due)
      expect(dispatch_registry.cleanup_calls).to eq(1)
    end

    it 'handles recovery and cleanup errors' do
      configuration.enable_dispatch_recovery = true
      allow(coordinator).to receive(:each_enabled_entry).and_raise(StandardError, 'boom')

      coordinator.send(:recover_missed_runs)
      expect(logger_io.string).to include('Error during missed-run recovery')

      configuration.backend = Class.new do
        def dispatch_registry
          raise 'cleanup boom'
        end
      end.new
      coordinator.send(:cleanup_old_dispatch_records, 10)
      expect(logger_io.string).to include('Error cleaning up old dispatch records')
    end

    it 'reports already dispatched state and lock acquisition failures' do
      dispatch_registry = instance_double(Kaal::Dispatch::MemoryEngine, dispatched?: true)
      allow(backend).to receive(:dispatch_registry).and_return(dispatch_registry)
      fire_time = Time.utc(2026, 1, 1, 0, 0, 0)

      expect(coordinator.send(:already_dispatched?, 'job:a', fire_time)).to be(true)

      configuration.backend = Class.new do
        def acquire(*)
          raise 'lock boom'
        end
      end.new
      expect(coordinator.send(:acquire_lock, 'lock:key')).to be(false)
      expect(logger_io.string).to include('Lock acquisition failed')
    end

    it 'dispatches work, generates keys, and sleeps safely' do
      calls = []
      callable_entry = Kaal::Registry::Entry.new(
        key: 'job:a',
        cron: '* * * * *',
        enqueue: ->(**kwargs) { calls << kwargs }
      ).freeze
      fire_time = Time.utc(2026, 1, 1, 0, 0, 0)

      coordinator.send(:dispatch_work, callable_entry, fire_time)
      expect(calls.first[:idempotency_key]).to include('ops-job:a')
      expect(coordinator.send(:generate_lock_key, 'job:a', fire_time)).to eq("ops:dispatch:job:a:#{fire_time.to_i}")
      expect(coordinator.send(:generate_delayed_lock_key, 'job:a')).to eq('ops:delayed_dispatch:job:a')

      tick_cv = Object.new
      tick_cv.define_singleton_method(:wait) { |_mutex, _interval| true }
      coordinator.instance_variable_set(:@tick_cv, tick_cv)
      coordinator.send(:sleep_until_next_tick)

      failing_tick_cv = Object.new
      failing_tick_cv.define_singleton_method(:wait) { |_mutex, _interval| raise StandardError, 'sleep boom' }
      coordinator.instance_variable_set(:@tick_cv, failing_tick_cv)
      coordinator.send(:sleep_until_next_tick)
      expect(logger_io.string).to include('Sleep interrupted')
    end

    it 'covers running state, restart, and internal helpers' do
      allow(coordinator).to receive_messages(stop!: true, start!: :thread)
      expect(coordinator.running?).to be(false)
      expect(coordinator.restart!).to eq(:thread)
      expect(coordinator.send(:stop_requested?)).to be(false)
      coordinator.send(:request_stop)
      expect(coordinator.send(:find_occurrences, Fugit.parse_cron('*/5 * * * *'), Time.utc(2026, 1, 1), Time.utc(2026, 1, 1, 0, 10))).to be_a(Array)
      expect(coordinator.send(:generate_idempotency_key, 'job:a', Time.utc(2026, 1, 1))).to include('job:a')
      expect(coordinator.send(:scheduler_time_zone_resolver)).to be_a(Kaal::SchedulerTimeZoneResolver)
      expect(coordinator.send(:occurrence_finder)).to be_a(Kaal::OccurrenceFinder)
      expect(coordinator.send(:enabled_entry_enumerator)).to be_a(Kaal::EnabledEntryEnumerator)
      coordinator.send(:log_runtime_error, 'prefix', StandardError.new('boom'))
      coordinator.send(:log_configuration_error, 'prefix', Kaal::ConfigurationError.new('boom'))
      expect(logger_io.string).to include('prefix: boom', 'prefix due to configuration error: boom')
    end

    it 'covers loop shutdown and recovery edge branches' do
      coordinator.send(:reset!)
      coordinator.instance_variable_set(:@running, true)
      coordinator.instance_variable_set(:@stop_requested, true)
      coordinator.send(:run_loop)
      expect(coordinator.running?).to be(false)

      coordinator.instance_variable_set(:@running, true)
      coordinator.instance_variable_set(:@stop_requested, false)
      allow(coordinator).to receive(:execute_tick) do
        coordinator.instance_variable_set(:@stop_requested, true)
      end
      allow(coordinator).to receive(:sleep_until_next_tick)
      coordinator.send(:run_loop)
      expect(coordinator).to have_received(:execute_tick)
      expect(coordinator).to have_received(:sleep_until_next_tick)

      configuration.enable_dispatch_recovery = true
      allow(coordinator).to receive_messages(rand: 1, sleep: nil)
      allow(coordinator).to receive(:each_enabled_entry).and_raise(Kaal::ConfigurationError, 'bad recovery')
      expect { coordinator.send(:recover_missed_runs) }.to raise_error(Kaal::ConfigurationError, 'bad recovery')

      configuration.enable_log_dispatch_registry = true
      allow(coordinator).to receive_messages(parse_cron: Fugit.parse_cron('*/5 * * * *'), find_occurrences: [Time.utc(2026, 1, 1)])
      allow(coordinator).to receive(:already_dispatched?).and_raise(StandardError, 'dispatch check boom')
      expect(coordinator.send(:recover_entry, entry, Time.utc(2026, 1, 1), Time.utc(2026, 1, 1, 0, 5))).to eq(0)

      allow(coordinator).to receive(:parse_cron).and_raise(Kaal::ConfigurationError, 'bad entry config')
      expect do
        coordinator.send(:recover_entry, entry, Time.utc(2026, 1, 1), Time.utc(2026, 1, 1, 0, 5))
      end.to raise_error(Kaal::ConfigurationError, 'bad entry config')

      configuration.logger = nil
      allow(coordinator).to receive_messages(parse_cron: nil, already_dispatched?: true)
      expect(coordinator.send(:recover_entry, entry, Time.utc(2026, 1, 1), Time.utc(2026, 1, 1, 0, 5))).to eq(0)
      expect(coordinator.send(:recover_entry, entry, Time.utc(2026, 1, 1), Time.utc(2026, 1, 1, 0, 5))).to eq(0)
    end

    it 'covers calculation, cleanup, dispatch, and logger-nil branches' do
      allow(Time).to receive(:now).and_return(Time.utc(2026, 1, 1, 0, 0, 0))
      allow(coordinator).to receive_messages(
        parse_cron: Fugit.parse_cron('*/5 * * * *'),
        find_occurrences: [Time.utc(2025, 12, 31, 23, 55, 0)]
      )
      allow(coordinator).to receive(:dispatch_if_due)
      coordinator.send(:calculate_and_dispatch_due_times, entry)
      expect(coordinator).to have_received(:dispatch_if_due)

      allow(coordinator).to receive(:parse_cron).and_return(nil)
      expect(coordinator.send(:calculate_and_dispatch_due_times, entry)).to be_nil

      configuration.logger = nil
      configuration.backend = Object.new
      expect(coordinator.send(:cleanup_old_dispatch_records, 10)).to be_nil
      expect(coordinator.send(:already_dispatched?, 'job:a', Time.utc(2026, 1, 1))).to be(false)

      configuration.backend = nil
      expect(coordinator.send(:acquire_lock, 'lock:key')).to be(true)

      broken_entry = Kaal::Registry::Entry.new(key: 'job:a', cron: '* * * * *', enqueue: ->(**) { raise 'dispatch boom' }).freeze
      expect(coordinator.send(:dispatch_work, broken_entry, Time.utc(2026, 1, 1))).to be_nil

      configuration.logger = Logger.new(logger_io)
      configuration.backend = Class.new do
        def dispatch_registry
          raise 'dispatch lookup boom'
        end
      end.new
      expect(coordinator.send(:already_dispatched?, 'job:a', Time.utc(2026, 1, 1))).to be(false)

      registry.add(key: 'job:a', cron: '* * * * *', enqueue: ->(**) {})
      expect(coordinator.send(:each_enabled_entry).to_a.map(&:key)).to include('job:a')
    end

    it 'covers nil-logger branches for stop, parse, recovery, and reset' do
      configuration.logger = nil
      expect(coordinator.stop!).to be(true)

      expect(coordinator.send(:parse_cron, 'bad cron')).to be_nil

      configuration.enable_dispatch_recovery = false
      expect(coordinator.send(:recover_missed_runs)).to be_nil

      configuration.enable_dispatch_recovery = true
      allow(coordinator).to receive_messages(rand: 0, sleep: nil, each_enabled_entry: nil)
      expect(coordinator.send(:recover_missed_runs)).to be_nil

      allow(coordinator).to receive_messages(running?: true, stop!: true)
      expect(coordinator.send(:reset!)).to be_nil
    end

    it 'covers nil-logger branches for recovery, cleanup, and lock handling' do
      configuration.logger = nil
      allow(coordinator).to receive_messages(parse_cron: Fugit.parse_cron('*/5 * * * *'), find_occurrences: [Time.utc(2026, 1, 1)])
      allow(coordinator).to receive(:dispatch_if_due)
      expect(coordinator.send(:recover_entry, entry, Time.utc(2026, 1, 1), Time.utc(2026, 1, 1, 0, 5))).to eq(1)

      allow(coordinator).to receive_messages(
        parse_cron: Fugit.parse_cron('*/5 * * * *'),
        find_occurrences: [Time.utc(2026, 1, 1)],
        dispatch_if_due: nil
      )
      coordinator.send(:calculate_and_dispatch_due_times, entry)
      expect(coordinator).to have_received(:dispatch_if_due).at_least(:once)

      configuration.backend = Struct.new(:dispatch_registry).new(Object.new)
      expect(coordinator.send(:cleanup_old_dispatch_records, 10)).to be_nil

      configuration.backend = Struct.new(:dispatch_registry).new(
        Class.new do
          def cleanup(*)
            0
          end
        end.new
      )
      expect(coordinator.send(:cleanup_old_dispatch_records, 10)).to be_nil

      configuration.backend = Struct.new(:dispatch_registry).new(
        Class.new do
          def dispatched?(*)
            raise 'boom'
          end
        end.new
      )
      expect(coordinator.send(:already_dispatched?, 'job:a', Time.utc(2026, 1, 1))).to be(false)

      configuration.backend = Object.new.tap do |backend|
        backend.define_singleton_method(:acquire) { |_| raise 'boom' }
      end
      expect(coordinator.send(:acquire_lock, 'lock:key')).to be(false)

      allow(coordinator).to receive(:dispatch_if_due).and_call_original
      configuration.backend = Object.new.tap do |backend|
        backend.define_singleton_method(:acquire) { |_| false }
      end
      expect(coordinator.send(:dispatch_if_due, entry, Time.utc(2026, 1, 1), Time.utc(2026, 1, 1))).to be_nil

      configuration.backend = Object.new.tap do |backend|
        backend.define_singleton_method(:acquire) { |_| raise 'boom' }
      end
      expect(coordinator.send(:dispatch_if_due, entry, Time.utc(2026, 1, 1), Time.utc(2026, 1, 1))).to be_nil
    end

    it 'covers nil-logger branches for dispatch, sleep, and logger recovery' do
      configuration.logger = nil
      configuration.backend = Object.new.tap do |backend|
        backend.define_singleton_method(:acquire) { |_| false }
      end
      expect(coordinator.send(:dispatch_if_due, entry, Time.utc(2026, 1, 1), Time.utc(2026, 1, 1))).to be_nil

      bad_entry = Object.new
      bad_entry.define_singleton_method(:key) { raise 'boom' }
      expect(coordinator.send(:dispatch_if_due, bad_entry, Time.utc(2026, 1, 1), Time.utc(2026, 1, 1))).to be_nil

      tick_cv = Object.new
      tick_cv.define_singleton_method(:wait) { |_mutex, _interval| raise 'boom' }
      coordinator.instance_variable_set(:@tick_cv, tick_cv)
      expect(coordinator.send(:sleep_until_next_tick)).to be_nil

      callable_entry = Kaal::Registry::Entry.new(key: 'job:a', cron: '* * * * *', enqueue: ->(**) {}).freeze
      expect(coordinator.send(:dispatch_work, callable_entry, Time.utc(2026, 1, 1))).to be_nil
      configuration.logger = Logger.new(logger_io)
      broken_entry = Kaal::Registry::Entry.new(key: 'job:a', cron: '* * * * *', enqueue: ->(**) { raise 'boom' }).freeze
      expect(coordinator.send(:dispatch_work, broken_entry, Time.utc(2026, 1, 1))).to be(true)

      configuration.logger = nil
      coordinator.send(:log_configuration_error, 'prefix', Kaal::ConfigurationError.new('boom'))
      coordinator.send(:log_runtime_error, 'prefix', StandardError.new('boom'))
    end

    it 'covers nil-logger recovery and cleanup logging branches' do
      configuration.logger = nil
      configuration.enable_dispatch_recovery = true
      allow(coordinator).to receive_messages(rand: 0, sleep: nil, each_enabled_entry: nil)
      expect(coordinator.send(:recover_missed_runs)).to be_nil

      configuration.backend = Struct.new(:dispatch_registry).new(
        Class.new do
          def cleanup(*)
            1
          end
        end.new
      )
      expect(coordinator.send(:cleanup_old_dispatch_records, 10)).to be_nil

      configuration.backend = Class.new do
        def dispatch_registry
          raise 'boom'
        end
      end.new
      expect(coordinator.send(:cleanup_old_dispatch_records, 10)).to be_nil
    end

    it 'dispatches due delayed jobs in order and leaves future jobs untouched' do
      calls = []
      stub_const('CoordinatorDelayedJobTarget', Class.new do
        define_singleton_method(:perform_later) { |value| calls << value }
      end)

      backend.delayed_store.enqueue(
        job_id: 'job:b',
        run_at: Time.utc(2026, 1, 1, 0, 1, 0),
        job_class: 'CoordinatorDelayedJobTarget',
        args: ['b'],
        queue: nil
      )
      backend.delayed_store.enqueue(
        job_id: 'job:a',
        run_at: Time.utc(2026, 1, 1, 0, 1, 0),
        job_class: 'CoordinatorDelayedJobTarget',
        args: ['a'],
        queue: nil
      )
      backend.delayed_store.enqueue(
        job_id: 'job:future',
        run_at: Time.utc(2026, 1, 1, 0, 2, 0),
        job_class: 'CoordinatorDelayedJobTarget',
        args: ['future'],
        queue: nil
      )

      allow(Time).to receive(:now).and_return(Time.utc(2026, 1, 1, 0, 1, 0))
      coordinator.send(:dispatch_due_delayed_jobs)

      expect(calls).to eq(%w[a b])
      expect(backend.delayed_store.find_job('job:future')).to include(job_id: 'job:future')
    end

    it 'adds delayed-job claim jitter only for delete-confirmation stores' do
      jitter_store = Class.new do
        def claim_strategy
          :delete_confirmation
        end

        def pop_due(**)
          []
        end
      end.new

      allow(coordinator).to receive(:rand).and_return(0.4)
      allow(coordinator).to receive(:sleep)
      configuration.backend = Struct.new(:delayed_store).new(jitter_store)

      coordinator.send(:dispatch_due_delayed_jobs)

      expect(coordinator).to have_received(:sleep).with(be_within(0.0001).of(0.02))
    end

    it 'skips delayed-job claim jitter for atomic-pop and skip-locked stores' do
      atomic_store = Class.new do
        def claim_strategy
          :atomic_pop
        end

        def pop_due(**)
          []
        end
      end.new

      skip_locked_store = Class.new do
        def claim_strategy
          :skip_locked
        end

        def pop_due(**)
          []
        end
      end.new

      allow(coordinator).to receive(:sleep)
      configuration.backend = Struct.new(:delayed_store).new(atomic_store)
      coordinator.send(:dispatch_due_delayed_jobs)

      configuration.backend = Struct.new(:delayed_store).new(skip_locked_store)
      coordinator.send(:dispatch_due_delayed_jobs)

      expect(coordinator).not_to have_received(:sleep)
    end

    it 'stops delayed-job sweeping before claiming when stop is requested' do
      calls = []
      store = Class.new do
        def initialize(calls)
          @calls = calls
        end

        def claim_strategy
          :atomic_pop
        end

        def pop_due(**)
          @calls << :pop_due
          []
        end
      end.new(calls)

      configuration.backend = Struct.new(:delayed_store).new(store)
      coordinator.instance_variable_set(:@stop_requested, true)

      coordinator.send(:dispatch_due_delayed_jobs)

      expect(calls).to eq([])
    end

    it 'bounds delayed-job sweep batches per tick' do
      calls = []
      store = Class.new do
        def initialize(calls)
          @calls = calls
        end

        def claim_strategy
          :atomic_pop
        end

        def pop_due(**)
          @calls << :pop_due
          [{ job_id: "job:#{@calls.length}", run_at: Time.utc(2026, 1, 1), job_class: 'MissingDelayedJobTarget', args: [], queue: nil }]
        end
      end.new(calls)

      configuration.backend = Struct.new(:delayed_store).new(store)

      coordinator.send(:dispatch_due_delayed_jobs)

      expect(calls.length).to eq(Kaal::Coordinator::DELAYED_JOB_MAX_BATCHES_PER_TICK)
    end

    it 'logs delayed dispatch failures without re-inserting the claimed job' do
      backend.delayed_store.enqueue(
        job_id: 'job:a',
        run_at: Time.utc(2026, 1, 1, 0, 1, 0),
        job_class: 'MissingDelayedJobTarget',
        args: [],
        queue: nil
      )

      allow(Time).to receive(:now).and_return(Time.utc(2026, 1, 1, 0, 1, 0))
      coordinator.send(:dispatch_due_delayed_jobs)

      expect(logger_io.string).to include('Delayed job job:a dispatch failed after claim')
      expect(logger_io.string).to include('job was already claimed and will not be retried')
      expect(logger_io.string).to include('job_class="MissingDelayedJobTarget"')
      expect(backend.delayed_store.find_job('job:a')).to be_nil
    end

    it 'enforces delayed-job allow-lists at dispatch time before constantization' do
      configuration.delayed_job_allowed_class_prefixes = ['Allowed::']
      backend.delayed_store.enqueue(
        job_id: 'job:blocked',
        run_at: Time.utc(2026, 1, 1, 0, 1, 0),
        job_class: 'Disallowed::Job',
        args: [],
        queue: nil
      )

      allow(Time).to receive(:now).and_return(Time.utc(2026, 1, 1, 0, 1, 0))
      coordinator.send(:dispatch_due_delayed_jobs)

      expect(logger_io.string).to include('Delayed job job:blocked dispatch failed after claim')
      expect(logger_io.string).to include('job_class="Disallowed::Job"')
    end

    it 'covers delayed store lookup and lock-guard branches' do
      expect(coordinator.send(:delayed_store_for_tick)).to eq(backend.delayed_store)

      configuration.backend = nil
      expect(coordinator.send(:delayed_store_for_tick)).to be_nil

      configuration.backend = Object.new
      expect(coordinator.send(:delayed_store_for_tick)).to be_nil

      locked_store = Class.new do
        def requires_dispatch_lock?
          true
        end
      end.new
      allow(coordinator).to receive(:acquire_lock).and_return(false)
      expect(
        coordinator.send(
          :dispatch_delayed_job,
          { job_id: 'job:a', run_at: Time.utc(2026, 1, 1), job_class: 'MissingJob', args: [], queue: nil },
          locked_store
        )
      ).to be_nil
    end

    it 'covers delayed dispatch rescue and no-store sweep branches' do
      configuration.backend = Object.new
      expect { coordinator.send(:dispatch_due_delayed_jobs) }.not_to raise_error

      configuration.backend = Struct.new(:delayed_store).new(
        Class.new do
          def claim_strategy
            :atomic_pop
          end

          def pop_due(**)
            raise 'boom'
          end
        end.new
      )
      expect { coordinator.send(:dispatch_due_delayed_jobs) }.not_to raise_error
      expect(logger_io.string).to include('Delayed job dispatch failed')
    end
  end
end
