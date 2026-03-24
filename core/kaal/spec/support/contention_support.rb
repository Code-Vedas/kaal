# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
module KaalContentionSupport
  module_function

  def repeated_fire_times(base_time, iterations:)
    Array.new(iterations) { |index| base_time + (index * 60) }
  end

  def run_threaded_contention(fixed_times:, key:, namespace:, backend_factory:, node_count: 3, cron: '* * * * *')
    collector = CallCollector.new
    previous_dispatch_logging = Kaal.configuration.enable_log_dispatch_registry

    Kaal.configuration.enable_log_dispatch_registry = true

    with_stubbed_time_now(fixed_times.fetch(0)) do |set_time|
      nodes = build_nodes(
        node_count: node_count,
        key: key,
        cron: cron,
        namespace: namespace,
        collector: collector,
        backend_factory: backend_factory
      )
      iteration_results = run_iterations(fixed_times:, set_time:, collector:, nodes:)

      {
        nodes: nodes,
        calls: iteration_results.flat_map { |result| result.fetch(:calls) },
        iterations: iteration_results
      }
    end
  ensure
    reset_kaal_state(previous_dispatch_logging)
  end

  def fire_time_for(current_time)
    Time.utc(current_time.year, current_time.month, current_time.day, current_time.hour, current_time.min)
  end

  def assert_single_dispatch_per_iteration!(result)
    iterations = result.is_a?(Hash) ? result.fetch(:iterations) : result

    iterations.each do |iteration|
      calls = iteration.fetch(:calls)
      expected_fire_time = iteration.fetch(:expected_fire_time)

      raise "expected exactly one call, got #{calls.length}" unless calls.length == 1

      observed_fire_times = calls.map { |call| call.fetch(:fire_time) }.uniq
      next if observed_fire_times == [expected_fire_time]

      raise "expected fire times #{[expected_fire_time].inspect}, got #{observed_fire_times.inspect}"
    end
  end

  def build_nodes(node_count:, key:, cron:, namespace:, collector:, backend_factory:)
    Array.new(node_count) do |node_index|
      backend = backend_factory.call(node_index)
      configuration = build_configuration(backend:, namespace:)
      registry = build_registry(key:, cron:, node_index:, collector:)

      {
        backend: backend,
        configuration: configuration,
        coordinator: Kaal::Coordinator.new(configuration:, registry:)
      }
    end
  end
  private_class_method :build_nodes

  def run_iterations(fixed_times:, set_time:, collector:, nodes:)
    fixed_times.map do |fixed_time|
      set_time.call(fixed_time)
      collector.clear
      run_concurrent_ticks(nodes.map { |node| node.fetch(:coordinator) })

      {
        fixed_time: fixed_time,
        expected_fire_time: fire_time_for(fixed_time),
        calls: collector.snapshot
      }
    end
  end
  private_class_method :run_iterations

  def build_configuration(backend:, namespace:)
    configuration = Kaal::Configuration.new
    configuration.backend = backend
    configuration.namespace = namespace
    configuration.window_lookback = 65
    configuration.window_lookahead = 0
    configuration.lease_ttl = 120
    configuration.enable_dispatch_recovery = false
    configuration.recovery_startup_jitter = 0
    configuration
  end
  private_class_method :build_configuration

  def build_registry(key:, cron:, node_index:, collector:)
    registry = Kaal::Registry.new
    registry.add(
      key: key,
      cron: cron,
      enqueue: lambda do |fire_time:, idempotency_key:|
        collector.record(node_index:, fire_time:, idempotency_key:)
      end
    )
    registry
  end
  private_class_method :build_registry

  def run_concurrent_ticks(coordinators)
    barrier = Barrier.new(coordinators.length)
    failures = Queue.new

    threads = coordinators.map do |coordinator|
      Thread.new do
        barrier.wait
        coordinator.tick!
      rescue StandardError => e
        failures << e
      end
    end

    threads.each(&:join)
    raise failures.pop unless failures.empty?
  end
  private_class_method :run_concurrent_ticks

  def with_stubbed_time_now(initial_time)
    current_time = initial_time
    time_singleton = Time.singleton_class
    original_now = Time.method(:now)

    time_singleton.define_method(:now) { current_time }
    yield ->(new_time) { current_time = new_time }
  ensure
    time_singleton.define_method(:now, original_now) if defined?(time_singleton) && defined?(original_now)
  end
  private_class_method :with_stubbed_time_now

  def reset_kaal_state(previous_dispatch_logging)
    Kaal.configuration.enable_log_dispatch_registry = previous_dispatch_logging
    Kaal.reset_configuration!
    Kaal.reset_registry!
    Kaal.instance_variable_set(:@registration_service, nil)
  end
  private_class_method :reset_kaal_state

  class Barrier
    def initialize(size)
      @size = size
      @waiting = 0
      @mutex = Mutex.new
      @condition = ConditionVariable.new
    end

    def wait
      @mutex.synchronize do
        @waiting += 1
        if @waiting >= @size
          @condition.broadcast
        else
          @condition.wait(@mutex) until @waiting >= @size
        end
      end
    end
  end

  class CallCollector
    def initialize
      @calls = []
      @mutex = Mutex.new
    end

    def record(node_index:, fire_time:, idempotency_key:)
      @mutex.synchronize do
        @calls << {
          node_index: node_index,
          fire_time: fire_time,
          idempotency_key: idempotency_key
        }
      end
    end

    def clear
      @mutex.synchronize { @calls.clear }
    end

    def snapshot
      @mutex.synchronize { @calls.map(&:dup) }
    end
  end
end
