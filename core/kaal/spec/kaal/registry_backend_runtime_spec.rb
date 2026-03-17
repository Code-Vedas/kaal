# frozen_string_literal: true

require 'spec_helper'

module SpecSupport
  class FakeRedisClient
    def initialize
      @store = {}
      @hashes = Hash.new { |hash, key| hash[key] = {} }
      @scripts = []
    end

    attr_reader :scripts

    def set(key, value, **options)
      return nil if options.fetch(:nx) && @store.key?(key)

      @store[key] = { value: value, ttl_ms: options.fetch(:px) }
      'OK'
    end

    def eval(script, keys:, argv:)
      @scripts << script
      key = keys.first
      return 0 unless @store[key]&.fetch(:value, nil) == argv.first

      @store.delete(key)
      1
    end

    def setex(key, ttl, value)
      @store[key] = { value: value, ttl: ttl }
    end

    def get(key)
      @store[key]&.fetch(:value, nil)
    end

    def hset(key, field, value)
      @hashes[key][field] = value
    end

    def hget(key, field)
      @hashes[key][field]
    end

    def hdel(key, field)
      @hashes[key].delete(field)
    end

    def hvals(key)
      @hashes[key].values
    end
  end

  class FakeSignalModule
    def initialize
      @handlers = {}
    end

    attr_reader :handlers

    def trap(signal, handler = nil, &block)
      previous = @handlers[signal]
      @handlers[signal] = (block || handler)

      previous
    end
  end
end

RSpec.describe Kaal::Registry do
  describe Kaal::Registry do
    subject(:registry) { described_class.new }

    let(:callback) { ->(**) { :ok } }

    it 'adds, reads, and removes entries' do
      entry = registry.add(key: 'job:1', cron: '* * * * *', enqueue: callback)

      expect(registry.find('job:1')).to eq(entry)
      expect(registry.registered?('job:1')).to be(true)
      expect(registry.all).to eq([entry])
      expect(registry.size).to eq(1)
      expect(registry.count).to eq(1)
      expect(registry.to_a).to eq([{ key: 'job:1', cron: '* * * * *', enqueue: callback }])
      expect(registry.inspect).to include('job:1')
      expect(registry.each.to_a).to eq([entry])
      expect(registry.remove('job:1')).to eq(entry)
      expect(registry.clear).to eq(0)
    end

    it 'upserts existing entries' do
      registry.add(key: 'job:1', cron: '* * * * *', enqueue: callback)

      entry = registry.upsert(key: 'job:1', cron: '*/5 * * * *', enqueue: callback)

      expect(entry.cron).to eq('*/5 * * * *')
    end

    it 'rejects invalid entries and duplicate keys' do
      expect { registry.add(key: '', cron: '* * * * *', enqueue: callback) }.to raise_error(ArgumentError)
      expect { registry.add(key: 'job', cron: '', enqueue: callback) }.to raise_error(ArgumentError)
      expect { registry.add(key: 'job', cron: '* * * * *', enqueue: Object.new) }.to raise_error(ArgumentError)

      registry.add(key: 'job', cron: '* * * * *', enqueue: callback)
      expect { registry.add(key: 'job', cron: '* * * * *', enqueue: callback) }.to raise_error(Kaal::RegistryError)
    end
  end

  describe Kaal::Definition::Registry do
    subject(:registry) { described_class.new }

    it 'raises for abstract methods' do
      expect { registry.upsert_definition(key: 'x', cron: '* * * * *') }.to raise_error(NotImplementedError)
      expect { registry.remove_definition('x') }.to raise_error(NotImplementedError)
      expect { registry.find_definition('x') }.to raise_error(NotImplementedError)
      expect { registry.all_definitions }.to raise_error(NotImplementedError)
    end
  end

  describe Kaal::Dispatch::Registry do
    subject(:registry) { described_class.new }

    it 'raises for abstract methods' do
      expect { registry.log_dispatch('a', Time.now.utc, 'node') }.to raise_error(NotImplementedError)
      expect { registry.find_dispatch('a', Time.now.utc) }.to raise_error(NotImplementedError)
    end

    it 'returns false when no dispatch record exists' do
      concrete = Class.new(described_class) do
        def find_dispatch(*)
          nil
        end
      end.new

      expect(concrete.dispatched?('job:a', Time.utc(2026, 1, 1))).to be(false)
    end
  end

  describe Kaal::Definition::MemoryEngine do
    subject(:engine) { described_class.new }

    it 'stores and toggles persisted definitions' do
      engine.upsert_definition(key: 'job:a', cron: '* * * * *', enabled: true, source: 'code', metadata: {})
      engine.upsert_definition(key: 'job:b', cron: '* * * * *', enabled: false, source: 'code', metadata: {})

      expect(engine.enabled_definitions.map { |row| row[:key] }).to eq(['job:a'])
      expect(engine.enable_definition('job:b')[:enabled]).to be(true)
      expect(engine.disable_definition('job:a')[:enabled]).to be(false)
      expect(engine.enable_definition('missing')).to be_nil
    end
  end

  describe Kaal::Dispatch::MemoryEngine do
    subject(:engine) { described_class.new }

    let(:fire_time) { Time.utc(2026, 1, 1, 0, 0, 0) }

    it 'logs and clears dispatch records' do
      engine.log_dispatch('job:a', fire_time, 'node-1')

      expect(engine.dispatched?('job:a', fire_time)).to be(true)
      expect(engine.find_dispatch('job:a', fire_time)).to include(key: 'job:a', node_id: 'node-1')
      expect(engine.size).to eq(1)
      expect(engine.clear).to eq({})
    end
  end

  describe Kaal::Definition::RedisEngine do
    subject(:engine) { described_class.new(redis, namespace: 'ops') }

    let(:redis) { SpecSupport::FakeRedisClient.new }

    it 'stores, finds, and removes definitions' do
      engine.upsert_definition(key: 'job:a', cron: '* * * * *', enabled: true, source: 'code', metadata: { 'a' => 1 })
      engine.upsert_definition(key: 'job:a', cron: '*/5 * * * *', enabled: false, source: 'code', metadata: {})

      expect(engine.find_definition('job:a')).to include(cron: '*/5 * * * *', enabled: false)
      expect(engine.all_definitions.map { |item| item[:key] }).to eq(['job:a'])
      expect(engine.remove_definition('job:a')).to include(key: 'job:a')
      expect(engine.find_definition('job:a')).to be_nil
    end

    it 'handles invalid stored payloads and timestamps' do
      redis.hset('ops:definitions', 'bad', '{')

      expect(engine.all_definitions).to eq([])
      expect(described_class.deserialize_payload('{')).to be_nil
      expect(described_class.parse_time('bad time')).to be_nil
    end

    it 'preserves disabled_at when a disabled definition stays disabled' do
      first = engine.upsert_definition(key: 'job:a', cron: '* * * * *', enabled: false, source: 'code', metadata: {})
      second = engine.upsert_definition(key: 'job:a', cron: '* * * * *', enabled: false, source: 'code', metadata: {})

      expect(second[:disabled_at].to_i).to eq(first[:disabled_at].to_i)
    end
  end

  describe Kaal::Dispatch::RedisEngine do
    subject(:engine) { described_class.new(redis, namespace: 'ops', ttl: 12) }

    let(:redis) { SpecSupport::FakeRedisClient.new }
    let(:fire_time) { Time.utc(2026, 1, 1, 0, 0, 0) }

    it 'stores dispatch records in redis' do
      engine.log_dispatch('job:a', fire_time, 'node-1', 'failed')

      record = engine.find_dispatch('job:a', fire_time)
      expect(record).to include(key: 'job:a', node_id: 'node-1', status: 'failed')
      expect(record[:fire_time]).to be_a(Time)
      expect(record[:dispatched_at]).to be_a(Time)
    end

    it 'returns nil for missing dispatch records' do
      expect(engine.find_dispatch('job:a', Time.utc(2026, 1, 1))).to be_nil
    end
  end

  describe Kaal::Backend::DispatchAttemptLogger do
    let(:logger_io) { StringIO.new }
    let(:logger) { Logger.new(logger_io) }
    let(:configuration) { Kaal::Configuration.new.tap { |config| config.logger = logger } }
    let(:dispatch_registry) { Kaal::Dispatch::MemoryEngine.new }

    it 'logs dispatch attempts when enabled' do
      configuration.enable_log_dispatch_registry = true
      described_class.new(
        configuration: configuration,
        dispatch_registry_provider: -> { dispatch_registry },
        node_id_provider: -> { 'node-xyz' }
      ).call('kaal:dispatch:job:alpha:100')

      expect(dispatch_registry.find_dispatch('job:alpha', Time.at(100))).to include(node_id: 'node-xyz')
    end

    it 'logs failures and no-ops when disabled' do
      described_class.new(
        configuration: configuration,
        dispatch_registry_provider: -> { raise 'boom' },
        logger: logger
      ).call('kaal:dispatch:job:beta:100')

      expect(logger_io.string).not_to include('Failed to log dispatch')

      configuration.enable_log_dispatch_registry = true
      described_class.new(
        configuration: configuration,
        dispatch_registry_provider: -> { raise 'boom' },
        logger: logger
      ).call('kaal:dispatch:job:beta:100')

      expect(logger_io.string).to include('Failed to log dispatch')
    end

    it 'covers registry logging with default dispatch logging and nil logger fallback' do
      configuration.enable_log_dispatch_registry = true
      Kaal.configuration.enable_log_dispatch_registry = true
      klass = Class.new do
        include Kaal::Backend::DispatchLogging

        def initialize(dispatch_registry)
          @dispatch_registry = dispatch_registry
        end

        attr_reader :dispatch_registry
      end

      klass.new(dispatch_registry).log_dispatch_attempt('kaal:dispatch:job:alpha:100')
      expect(dispatch_registry.find_dispatch('job:alpha', Time.at(100))).to include(status: 'dispatched')

      configuration.logger = nil
      expect(described_class.new(configuration:, dispatch_registry_provider: -> { raise 'boom' }).call('kaal:dispatch:job:alpha:100')).to be_nil
      configuration.enable_log_dispatch_registry = false
      Kaal.configuration.enable_log_dispatch_registry = false
      expect(described_class.new(configuration:, dispatch_registry_provider: -> { raise 'boom' }).call('kaal:dispatch:job:alpha:100')).to be_nil
    end

    it 'returns early when the dispatch registry provider returns nil' do
      configuration.enable_log_dispatch_registry = true

      expect(described_class.new(configuration:, dispatch_registry_provider: -> {}).call('kaal:dispatch:job:alpha:100')).to be_nil
    end
  end

  describe Kaal::Backend::DispatchLogging do
    it 'parses lock keys' do
      expect(described_class.parse_lock_key('kaal:dispatch:job:alpha:100')).to eq(['job:alpha', Time.at(100)])
    end

    it 'exposes default dispatch registry and instance parsing helpers' do
      klass = Class.new do
        include Kaal::Backend::DispatchLogging
      end
      instance = klass.new

      expect(instance.dispatch_registry).to be_nil
      expect(instance.parse_lock_key('kaal:dispatch:job:alpha:100')).to eq(['job:alpha', Time.at(100)])
      expect(instance.send(:dispatch_attempt_logger)).to be_a(Kaal::Backend::DispatchAttemptLogger)
    end
  end

  describe Kaal::Backend::Adapter do
    subject(:adapter) { described_class.new }

    it 'raises for abstract methods' do
      expect { adapter.acquire('x', 1) }.to raise_error(NotImplementedError)
      expect { adapter.release('x') }.to raise_error(NotImplementedError)
      expect(adapter.definition_registry).to be_nil
    end

    it 'returns nil when with_lock cannot acquire and releases after yielding' do
      concrete = Class.new(described_class) do
        attr_reader :released

        def initialize
          super
          @allow = false
          @released = []
        end

        def allow!
          @allow = true
        end

        def acquire(*)
          @allow
        end

        def release(key)
          @released << key
        end
      end.new

      expect(concrete.with_lock('x', ttl: 1) { :ok }).to be_nil
      concrete.allow!
      expect(concrete.with_lock('x', ttl: 1) { :ok }).to eq(:ok)
      expect(concrete.released).to eq(['x'])
    end
  end

  describe Kaal::Backend::NullAdapter do
    subject(:adapter) { described_class.new }

    it 'always yields and returns true' do
      yielded = false

      expect(adapter.acquire('x', 1)).to be(true)
      expect(adapter.release('x')).to be(true)
      expect(adapter.with_lock('x', ttl: 1) { yielded = true }).to be(true)
      expect(yielded).to be(true)
    end
  end

  describe Kaal::Backend::MemoryAdapter do
    subject(:adapter) { described_class.new }

    it 'acquires and releases memory locks' do
      allow(Time).to receive(:now).and_return(Time.utc(2026, 1, 1, 0, 0, 0), Time.utc(2026, 1, 1, 0, 0, 0), Time.utc(2026, 1, 1, 0, 0, 2))

      expect(adapter.acquire('lock', 1)).to be(true)
      expect(adapter.release('lock')).to be(true)
      expect(adapter.release('missing')).to be(false)
      expect(adapter.dispatch_registry).to be_a(Kaal::Dispatch::MemoryEngine)
      expect(adapter.definition_registry).to be_a(Kaal::Definition::MemoryEngine)
    end

    it 'covers failed acquisition without dispatch logging' do
      allow(Time).to receive(:now).and_return(Time.utc(2026, 1, 1), Time.utc(2026, 1, 1))

      expect(adapter.acquire('lock', 60)).to be(true)
      expect(adapter.acquire('lock', 60)).to be(false)
    end
  end

  describe Kaal::Backend::RedisAdapter do
    subject(:adapter) { described_class.new(redis, namespace: 'ops') }

    let(:redis) { SpecSupport::FakeRedisClient.new }

    it 'acquires and releases redis locks' do
      allow(SecureRandom).to receive(:uuid).and_return('token-1', 'token-2')

      expect(adapter.acquire('lock', 5)).to be(true)
      expect(adapter.acquire('lock', 5)).to be(false)
      expect(adapter.release('lock')).to be(true)
      expect(adapter.release('missing')).to be(false)
      expect(adapter.dispatch_registry).to be_a(Kaal::Dispatch::RedisEngine)
      expect(adapter.definition_registry).to be_a(Kaal::Definition::RedisEngine)
    end

    it 'validates the redis client interface' do
      expect { described_class.new(Object.new) }.to raise_error(ArgumentError)
    end

    it 'wraps acquire and release failures' do
      broken_redis_class = Class.new do
        def set(*)
          raise StandardError, 'set failed'
        end

        def eval(*)
          raise StandardError, 'eval failed'
        end
      end
      broken_adapter = described_class.new(broken_redis_class.new)

      expect { broken_adapter.acquire('x', 1) }.to raise_error(Kaal::Backend::LockAdapterError)

      broken_adapter.instance_variable_set(:@lock_values, { 'x' => { value: 'v', expires_at: Time.now + 1 } })
      expect { broken_adapter.release('x') }.to raise_error(Kaal::Backend::LockAdapterError)
    end
  end

  describe Kaal::Backend::DispatchRegistryAccessor do
    let(:logger) { Logger.new(StringIO.new) }
    let(:configuration) { Kaal::Configuration.new.tap { |config| config.logger = logger } }

    it 'returns dispatch status through the configured backend' do
      registry = Kaal::Dispatch::MemoryEngine.new
      fire_time = Time.utc(2026, 1, 1, 0, 0, 0)
      registry.log_dispatch('job:a', fire_time, 'node-1')
      configuration.backend = Struct.new(:dispatch_registry).new(registry)

      accessor = described_class.new(configuration: configuration)
      expect(accessor.registry).to eq(registry)
      expect(accessor.dispatched?('job:a', fire_time)).to be(true)
    end

    it 'returns false or nil when the backend is unavailable or raises' do
      accessor = described_class.new(configuration: configuration)
      expect(accessor.registry).to be_nil
      expect(accessor.dispatched?('job:a', Time.now.utc)).to be(false)

      backend_class = Class.new do
        def dispatch_registry
          raise StandardError, 'boom'
        end
      end
      configuration.backend = backend_class.new

      expect(accessor.registry).to be_nil
      expect(accessor.dispatched?('job:a', Time.now.utc)).to be(false)
    end

    it 'covers logger-nil and unsupported-backend branches' do
      configuration.logger = nil
      configuration.backend = Class.new do
        def dispatch_registry
          raise 'boom'
        end
      end.new

      accessor = described_class.new(configuration:)
      expect(accessor.registry).to be_nil
      expect(accessor.dispatched?('job:a', Time.utc(2026, 1, 1))).to be(false)

      configuration.backend = Object.new
      expect(accessor.registry).to be_nil
      expect(accessor.dispatched?('job:a', Time.utc(2026, 1, 1))).to be(false)
    end
  end

  describe Kaal::Definitions::RegistryAccessor do
    let(:configuration) { Kaal::Configuration.new }

    it 'returns configured registries or falls back' do
      registry = Kaal::Definition::MemoryEngine.new
      configuration.backend = Struct.new(:definition_registry).new(registry)

      expect(described_class.new(configuration: configuration, fallback_registry_provider: -> { :fallback }).call).to eq(registry)
    end

    it 'falls back when the backend is absent or misbehaves' do
      accessor = described_class.new(configuration: configuration, fallback_registry_provider: -> { :fallback })
      expect(accessor.call).to eq(:fallback)

      configuration.backend = Object.new
      expect(accessor.call).to eq(:fallback)
    end
  end

  describe Kaal::RuntimeContext do
    it 'resolves default environment names and relative paths' do
      context = described_class.default(env: { 'APP_ENV' => 'production' }, root_path: '/tmp/app')

      expect(context.environment_name).to eq('production')
      expect(context.resolve_path('config/kaal.rb')).to eq('/tmp/app/config/kaal.rb')
      expect(context.resolve_path('/etc/kaal.rb')).to eq('/etc/kaal.rb')
      expect(described_class.environment_name_from({})).to eq('development')
    end
  end

  describe Kaal::SchedulerBootLoader do
    let(:logger) { Logger.new(StringIO.new) }

    it 'warns for missing files in warn mode and loads files in error mode' do
      configuration = Kaal::Configuration.new
      configuration.scheduler_missing_file_policy = :warn
      configuration.scheduler_config_path = 'missing.yml'
      load_calls = []
      context = Kaal::RuntimeContext.new(root_path: Dir.pwd, environment_name: 'development')
      loader = described_class.new(
        configuration_provider: -> { configuration },
        logger: logger,
        runtime_context: context,
        load_scheduler_file: -> { load_calls << :loaded }
      )

      expect(loader.load_on_boot).to be_nil

      configuration.scheduler_missing_file_policy = :error
      expect(loader.load_on_boot!).to eq([:loaded])
      expect(load_calls).to eq([:loaded])
    end

    it 'loads an existing scheduler file and swallows configuration lookup name errors' do
      root = Dir.mktmpdir
      FileUtils.mkdir_p(File.join(root, 'config'))
      File.write(File.join(root, 'config', 'scheduler.yml'), "defaults:\n  jobs: []\n")
      configuration = Kaal::Configuration.new
      configuration.scheduler_config_path = 'config/scheduler.yml'
      context = Kaal::RuntimeContext.new(root_path: root, environment_name: 'development')
      load_calls = []

      loader = described_class.new(
        configuration_provider: -> { configuration },
        logger: logger,
        runtime_context: context,
        load_scheduler_file: -> { load_calls << :loaded }
      )
      noisy_loader = described_class.new(
        configuration_provider: -> { raise NameError, 'missing config' },
        logger: logger,
        runtime_context: context,
        load_scheduler_file: -> { :loaded }
      )

      expect(loader.load_on_boot!).to eq([:loaded])
      expect(load_calls).to eq([:loaded])
      expect(noisy_loader.load_on_boot!).to be_nil
    ensure
      FileUtils.remove_entry(root)
    end

    it 'covers blank-path and nil-logger branches' do
      configuration = Kaal::Configuration.new
      configuration.scheduler_config_path = ' '
      context = Kaal::RuntimeContext.new(root_path: Dir.pwd, environment_name: 'development')
      loader = described_class.new(
        configuration_provider: -> { configuration },
        logger: nil,
        runtime_context: context,
        load_scheduler_file: -> { :loaded }
      )
      expect(loader.load_on_boot!).to be_nil

      noisy_loader = described_class.new(
        configuration_provider: -> { raise NameError, 'missing config' },
        logger: nil,
        runtime_context: context,
        load_scheduler_file: -> { :loaded }
      )
      expect(noisy_loader.load_on_boot!).to be_nil
    end

    it 'covers missing files without a logger' do
      configuration = Kaal::Configuration.new
      configuration.scheduler_config_path = 'missing.yml'
      context = Kaal::RuntimeContext.new(root_path: Dir.pwd, environment_name: 'development')
      loader = described_class.new(
        configuration_provider: -> { configuration },
        logger: nil,
        runtime_context: context,
        load_scheduler_file: -> { :loaded }
      )

      expect(loader.load_on_boot!).to be_nil
    end
  end

  describe Kaal::SignalHandlerChain do
    let(:logger) { Logger.new(StringIO.new) }

    it 'invokes callable handlers and ignores reserved command handlers' do
      calls = []
      zero_arity = -> { calls << :zero }
      variable_arity = ->(*args) { calls << args }

      described_class.new(signal: 'TERM', previous_handler: zero_arity, logger: logger).call('TERM', 15)
      described_class.new(signal: 'TERM', previous_handler: variable_arity, logger: logger).call('TERM', 15)
      described_class.new(signal: 'TERM', previous_handler: 'DEFAULT', logger: logger).call('TERM')
      described_class.new(signal: 'TERM', previous_handler: 'echo noop', logger: logger).call('TERM')

      expect(calls).to include(:zero, ['TERM', 15])
    end

    it 'ignores unsupported handler types and command strings without a logger' do
      expect(described_class.new(signal: 'TERM', previous_handler: 123, logger: logger).call('TERM')).to be_nil
      expect(described_class.new(signal: 'TERM', previous_handler: 'echo hi', logger: nil).call('TERM')).to be_nil
    end

    it 'passes a fixed number of args to fixed-arity callables' do
      calls = []
      handler = ->(signal) { calls << signal }

      described_class.new(signal: 'TERM', previous_handler: handler, logger: logger).call('TERM', 15)
      expect(calls).to eq(['TERM'])
    end
  end

  describe Kaal::SignalHandlerInstaller do
    it 'installs handlers while preserving previous ones' do
      signal_module = SpecSupport::FakeSignalModule.new
      signal_module.trap('TERM', proc {})
      signal_module.trap('INT', 'IGNORE')
      calls = []

      previous_handlers = described_class.new(signal_module: signal_module).install do |signal, previous_handler|
        calls << [signal, previous_handler.class.name]
      end

      expect(previous_handlers.keys).to contain_exactly('TERM', 'INT')
      signal_module.handlers['TERM'].call
      signal_module.handlers['INT'].call
      expect(calls.any? { |item| item.first == 'TERM' }).to be(true)
    end
  end
end
