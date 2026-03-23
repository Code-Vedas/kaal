# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'
require 'redis'

RSpec.describe Kaal::Hanami do
  let(:fake_app_class) do
    middleware = Class.new do
      attr_reader :uses

      def initialize
        @uses = []
      end

      def use(*args, **kwargs)
        @uses << [args, kwargs]
      end
    end.new

    config = Struct.new(:root, :env, :middleware).new(nil, nil, middleware)

    Class.new do
      define_singleton_method(:config) { config }
    end
  end

  it 'has a version number and exposes the middleware class' do
    expect(described_class::VERSION).to eq('0.2.1')
    expect(described_class::Middleware).to be_a(Class)
  end

  it 'configures the Hanami middleware stack' do
    described_class.configure!(fake_app_class, namespace: 'hanami-spec')

    args, kwargs = fake_app_class.config.middleware.uses.fetch(0)
    expect(args.first).to eq(Kaal::Hanami::Middleware)
    expect(kwargs.fetch(:hanami_app)).to eq(fake_app_class)
    expect(kwargs.fetch(:namespace)).to eq('hanami-spec')
  end

  it 'detects supported database adapters and builds matching SQL backends' do
    sqlite_db = Struct.new(:database_type).new(:sqlite)
    postgres_db = Struct.new(:database_type).new(:postgres)
    mysql_db = Struct.new(:database_type).new(:mysql2)
    unknown_db = Struct.new(:database_type).new(:oracle)

    expect(described_class.detect_backend_name(sqlite_db)).to eq('sqlite')
    expect(described_class.detect_backend_name(postgres_db)).to eq('postgres')
    expect(described_class.detect_backend_name(mysql_db)).to eq('mysql')
    expect(described_class.detect_backend_name(unknown_db)).to be_nil
    expect(described_class.detect_backend_name(unknown_db, adapter: 'trilogy')).to eq('mysql')

    database = Sequel.sqlite

    expect(described_class.configure_backend!(database:, adapter: 'sqlite')).to be_a(Kaal::Backend::DatabaseAdapter)

    Kaal.reset_configuration!
    expect(described_class.configure_backend!(database:, adapter: 'postgres')).to be_a(Kaal::Backend::PostgresAdapter)

    Kaal.reset_configuration!
    expect(described_class.configure_backend!(database:, adapter: 'mysql')).to be_a(Kaal::Backend::MySQLAdapter)

    Kaal.reset_configuration!
    expect { described_class.configure_backend!(database:, adapter: 'oracle') }.to raise_error(ArgumentError, /Unsupported Hanami datastore backend/)

    Kaal.reset_configuration!
    expect { described_class.configure_backend!(adapter: 'sqlite') }.to raise_error(
      ArgumentError,
      /database is required when adapter is provided/
    )
  ensure
    database&.disconnect
  end

  it 'defaults to the memory backend when no backend inputs are provided' do
    expect(described_class.configure_backend!).to be_a(Kaal::Backend::MemoryAdapter)
  end

  it 'builds a redis backend when a redis client is provided' do
    fake_redis = Class.new do
      def set(*) = 'OK'
      def eval(*) = 0
    end.new

    Kaal.configuration.namespace = 'hanami-redis'
    backend = described_class.configure_backend!(redis: fake_redis)

    expect(backend).to be_a(Kaal::Backend::RedisAdapter)
    expect(Kaal.configuration.backend).to eq(backend)
  end

  it 'returns the inferred SQL backend when database is provided without adapter' do
    database = Sequel.sqlite
    backend = described_class.configure_backend!(database:)

    expect(backend).to be_a(Kaal::Backend::DatabaseAdapter)
    expect(Kaal.configuration.backend).to eq(backend)
  ensure
    database&.disconnect
  end

  it 'preserves an explicit backend override' do
    custom_backend = Kaal::Backend::MemoryAdapter.new
    Kaal.configuration.backend = custom_backend

    database = Sequel.sqlite

    expect(described_class.configure_backend!(database:)).to eq(custom_backend)
    expect(Kaal.configuration.backend).to eq(custom_backend)
  ensure
    database&.disconnect
  end

  it 'falls back to adapter_scheme and nil-safe adapter detection' do
    scheme_only_db = Class.new do
      def adapter_scheme
        :postgres
      end
    end.new

    expect(described_class.detect_backend_name(nil)).to be_nil
    expect(described_class.detect_backend_name(scheme_only_db)).to eq('postgres')
  end

  it 'raises when backend inference is unsupported without an explicit adapter override' do
    unsupported_db = Struct.new(:database_type).new(:oracle)

    expect { described_class.configure_backend!(database: unsupported_db) }
      .to raise_error(ArgumentError, /Unsupported Hanami datastore backend; use memory, redis, sqlite, postgres, or mysql/)
  end

  it 'registers the app, loads scheduler definitions, and does not auto-start by default' do
    Dir.mktmpdir('kaal-hanami-register-') do |root|
      database_path = File.join(root, 'db', 'kaal.sqlite3')
      FileUtils.mkdir_p(File.dirname(database_path))
      FileUtils.mkdir_p(File.join(root, 'config'))
      File.write(
        File.join(root, 'config', 'scheduler.yml'),
        YAML.dump(
          'defaults' => {
            'jobs' => [
              {
                'key' => 'hanami:test',
                'cron' => '* * * * *',
                'job_class' => 'KaalHanamiSpecJob',
                'enabled' => true
              }
            ]
          }
        )
      )

      stub_const('KaalHanamiSpecJob', Class.new do
        def self.perform(*); end
      end)

      fake_app_class.config.root = root
      fake_app_class.config.env = :test
      database = Sequel.sqlite(database_path)
      KaalHanamiDummyAppSupport.create_sql_schema(database, 'sqlite')

      expect(described_class.register!(fake_app_class, database:, namespace: 'hanami-spec')).to eq(fake_app_class)

      expect(Kaal.configuration.namespace).to eq('hanami-spec')
      expect(Kaal.configuration.scheduler_config_path).to eq('config/scheduler.yml')
      expect(Kaal.configuration.backend).to be_a(Kaal::Backend::DatabaseAdapter)
      expect(Kaal.registered?(key: 'hanami:test')).to be(true)
      expect(Kaal.running?).to be(false)
    ensure
      database&.disconnect
    end
  end

  it 'preserves the default scheduler path when register! is called with nil' do
    fake_app_class.config.root = Dir.pwd
    allow(described_class).to receive(:load_scheduler_file!)

    described_class.register!(fake_app_class, scheduler_config_path: nil)

    expect(Kaal.configuration.scheduler_config_path).to eq('config/scheduler.yml')
  end

  it 'preserves the default scheduler path when register! is called with blank scheduler_config_path' do
    fake_app_class.config.root = Dir.pwd
    allow(described_class).to receive(:load_scheduler_file!)

    described_class.register!(fake_app_class, scheduler_config_path: '   ')

    expect(Kaal.configuration.scheduler_config_path).to eq('config/scheduler.yml')
  end

  it 'preserves the default namespace when register! is called with a blank namespace' do
    fake_app_class.config.root = Dir.pwd
    allow(described_class).to receive(:load_scheduler_file!)

    described_class.register!(fake_app_class, namespace: '   ')

    expect(Kaal.configuration.namespace).to eq('kaal')
  end

  it 'uses an explicit backend object passed to register!' do
    fake_app_class.config.root = Dir.pwd
    backend = Kaal::Backend::MemoryAdapter.new
    allow(described_class).to receive(:load_scheduler_file!)

    described_class.register!(fake_app_class, backend:)

    expect(Kaal.configuration.backend).to eq(backend)
  end

  it 'loads scheduler files with fallback environment detection' do
    Dir.mktmpdir('kaal-hanami-load-') do |root|
      FileUtils.mkdir_p(File.join(root, 'config'))
      File.write(
        File.join(root, 'config', 'scheduler.yml'),
        YAML.dump(
          'defaults' => {
            'jobs' => []
          },
          'test' => {
            'jobs' => [
              {
                'key' => 'hanami:load',
                'cron' => '* * * * *',
                'job_class' => 'KaalHanamiLoadJob',
                'enabled' => true
              }
            ]
          }
        )
      )

      stub_const('KaalHanamiLoadJob', Class.new do
        def self.perform(*); end
      end)

      original_hanami_env = ENV.fetch('HANAMI_ENV', nil)
      ENV['HANAMI_ENV'] = 'test'
      described_class.load_scheduler_file!(root:, environment: nil)

      expect(Kaal.registered?(key: 'hanami:load')).to be(true)
    ensure
      ENV['HANAMI_ENV'] = original_hanami_env
    end
  end

  it 'delegates the explicit lifecycle helpers to Kaal' do
    allow(Kaal).to receive(:start!).and_return(Thread.current)
    allow(Kaal).to receive(:stop!).with(timeout: 12).and_return(true)

    expect(described_class.start!).to eq(Thread.current)
    expect(described_class.stop!(timeout: 12)).to be(true)
  end

  it 'resolves private helper fallbacks for plain objects' do
    plain_app = Object.new

    expect(described_class.send(:build_backend, 'unknown', nil)).to be_nil
    expect(described_class.send(:database_adapter_name, plain_app)).to eq('')
    expect(described_class.send(:root_path_for, plain_app, root: nil)).to eq(Pathname.new(Dir.pwd))
    expect(described_class.send(:root_path_for, plain_app, root: '/tmp/kaal-hanami')).to eq(Pathname.new('/tmp/kaal-hanami'))
    expect(described_class.send(:environment_name_for, plain_app, environment: nil)).to eq('development')
    expect(described_class.send(:environment_name_for, plain_app, environment: 'test')).to eq('test')
  end

  it 'falls back to runtime context when Hanami.env is unavailable' do
    plain_app = Object.new

    original_hanami_env = ENV.fetch('HANAMI_ENV', nil)
    ENV['HANAMI_ENV'] = 'test'
    allow(Hanami).to receive(:respond_to?).with(:env).and_return(false)

    expect(described_class.send(:environment_name_for, plain_app, environment: nil)).to eq('test')
  ensure
    ENV['HANAMI_ENV'] = original_hanami_env
  end

  it 'falls back to generic runtime environment detection when Hanami env sources are unavailable' do
    original_hanami_env = ENV.fetch('HANAMI_ENV', nil)
    ENV.delete('HANAMI_ENV')
    allow(Hanami).to receive(:respond_to?).with(:env).and_return(false)

    expect(described_class.send(:runtime_environment_name, nil)).to eq('development')
  ensure
    ENV['HANAMI_ENV'] = original_hanami_env
  end

  it 'installs a shutdown hook only when managed startup is requested' do
    Dir.mktmpdir('kaal-hanami-start-') do |root|
      fake_app_class.config.root = root
      FileUtils.mkdir_p(File.join(root, 'config'))
      File.write(File.join(root, 'config', 'scheduler.yml'), YAML.dump('defaults' => { 'jobs' => [] }))

      allow(described_class).to receive(:install_shutdown_hook)
      allow(Kaal).to receive(:start!).and_return(Thread.current)
      allow(Kaal).to receive(:running?).and_return(false, false)

      described_class.register!(fake_app_class, start_scheduler: true)

      expect(described_class).to have_received(:install_shutdown_hook).once
    end
  end

  it 'does not install a managed shutdown hook when the scheduler is already running' do
    Dir.mktmpdir('kaal-hanami-running-') do |root|
      fake_app_class.config.root = root
      FileUtils.mkdir_p(File.join(root, 'config'))
      File.write(File.join(root, 'config', 'scheduler.yml'), YAML.dump('defaults' => { 'jobs' => [] }))

      allow(described_class).to receive(:install_shutdown_hook)
      allow(Kaal).to receive_messages(start!: nil, running?: true)

      described_class.register!(fake_app_class, start_scheduler: true)

      expect(Kaal).not_to have_received(:start!)
      expect(described_class).not_to have_received(:install_shutdown_hook)
    end
  end

  it 'registers Kaal through the middleware class' do
    downstream = ->(env) { [200, { 'content-type' => 'text/plain' }, [env.fetch('PATH_INFO')]] }

    allow(described_class).to receive(:register!).with(
      fake_app_class,
      backend: nil,
      database: nil,
      redis: nil,
      scheduler_config_path: 'config/scheduler.yml',
      namespace: 'hanami-middleware',
      start_scheduler: false,
      adapter: nil,
      root: nil,
      environment: nil
    )
    middleware = described_class::Middleware.new(downstream, hanami_app: fake_app_class, namespace: 'hanami-middleware')

    expect(middleware.call('PATH_INFO' => '/')).to eq([200, { 'content-type' => 'text/plain' }, ['/']])
    expect(described_class).to have_received(:register!).with(
      fake_app_class,
      backend: nil,
      database: nil,
      redis: nil,
      scheduler_config_path: 'config/scheduler.yml',
      namespace: 'hanami-middleware',
      start_scheduler: false,
      adapter: nil,
      root: nil,
      environment: nil
    )
  end

  it 'avoids duplicate shutdown hook registration and swallows stop errors in the managed hook' do
    logger = instance_double(Logger, error: nil)
    Kaal.configuration.logger = logger

    allow(Kernel).to receive(:at_exit).and_yield
    allow(Kaal).to receive(:running?).and_return(true)
    allow(described_class).to receive(:stop!).and_raise(StandardError, 'stop failure')

    expect { described_class.send(:install_shutdown_hook) }.not_to raise_error
    expect { described_class.send(:install_shutdown_hook) }.not_to raise_error
    expect(Kernel).to have_received(:at_exit).once
    expect(logger).to have_received(:error).with(/Failed to stop Kaal during Hanami shutdown: stop failure/)
  end

  it 'swallows managed shutdown stop errors when no logger is configured' do
    Kaal.configuration.logger = nil

    allow(Kernel).to receive(:at_exit).and_yield
    allow(Kaal).to receive(:running?).and_return(true)
    allow(described_class).to receive(:stop!).and_raise(StandardError, 'stop failure')

    expect { described_class.send(:install_shutdown_hook) }.not_to raise_error
  end

  it 'skips the managed shutdown hook body when the scheduler is not running' do
    allow(Kernel).to receive(:at_exit).and_yield
    allow(Kaal).to receive(:running?).and_return(false)
    allow(described_class).to receive(:stop!)

    described_class.send(:install_shutdown_hook)

    expect(described_class).not_to have_received(:stop!)
  end
end
