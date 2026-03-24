# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'
require 'redis'

RSpec.describe Kaal::Sinatra do
  let(:fake_app_class) do
    Class.new do
      def self.settings
        self
      end

      def self.root
        @root
      end

      def self.root=(value)
        @root = value
      end

      def self.environment
        :test
      end
    end
  end

  it 'has a version number and exposes the extension module' do
    expect(described_class::VERSION).to eq('0.3.0')
    expect(described_class::Extension).to be_a(Module)
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
    expect { described_class.configure_backend!(database:, adapter: 'oracle') }.to raise_error(ArgumentError, /Unsupported Sinatra datastore backend/)

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

    Kaal.configuration.namespace = 'sinatra-redis'
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
      .to raise_error(ArgumentError, /Unsupported Sinatra datastore backend; use memory, redis, sqlite, postgres, or mysql/)
  end

  it 'registers the app, loads scheduler definitions, and does not auto-start by default' do
    Dir.mktmpdir('kaal-sinatra-register-') do |root|
      database_path = File.join(root, 'db', 'kaal.sqlite3')
      FileUtils.mkdir_p(File.dirname(database_path))
      FileUtils.mkdir_p(File.join(root, 'config'))
      File.write(
        File.join(root, 'config', 'scheduler.yml'),
        YAML.dump(
          'defaults' => {
            'jobs' => [
              {
                'key' => 'sinatra:test',
                'cron' => '* * * * *',
                'job_class' => 'KaalSinatraSpecJob',
                'enabled' => true
              }
            ]
          }
        )
      )

      stub_const('KaalSinatraSpecJob', Class.new do
        def self.perform(*); end
      end)

      fake_app_class.root = root
      database = Sequel.sqlite(database_path)
      KaalSinatraDummyAppSupport.create_sql_schema(database, 'sqlite')

      expect(described_class.register!(fake_app_class, database:, namespace: 'sinatra-spec')).to eq(fake_app_class)

      expect(Kaal.configuration.namespace).to eq('sinatra-spec')
      expect(Kaal.configuration.scheduler_config_path).to eq('config/scheduler.yml')
      expect(Kaal.configuration.backend).to be_a(Kaal::Backend::DatabaseAdapter)
      expect(Kaal.registered?(key: 'sinatra:test')).to be(true)
      expect(Kaal.running?).to be(false)
    ensure
      database&.disconnect
    end
  end

  it 'preserves the default scheduler path when register! is called with nil' do
    fake_app_class.root = Dir.pwd
    allow(described_class).to receive(:load_scheduler_file!)

    described_class.register!(fake_app_class, scheduler_config_path: nil)

    expect(Kaal.configuration.scheduler_config_path).to eq('config/scheduler.yml')
  end

  it 'preserves the default scheduler path when register! is called with blank scheduler_config_path' do
    fake_app_class.root = Dir.pwd
    allow(described_class).to receive(:load_scheduler_file!)

    described_class.register!(fake_app_class, scheduler_config_path: '   ')

    expect(Kaal.configuration.scheduler_config_path).to eq('config/scheduler.yml')
  end

  it 'preserves the default namespace when register! is called with a blank namespace' do
    fake_app_class.root = Dir.pwd
    allow(described_class).to receive(:load_scheduler_file!)

    described_class.register!(fake_app_class, namespace: '   ')

    expect(Kaal.configuration.namespace).to eq('kaal')
  end

  it 'uses an explicit backend object passed to register!' do
    fake_app_class.root = Dir.pwd
    backend = Kaal::Backend::MemoryAdapter.new
    allow(described_class).to receive(:load_scheduler_file!)

    described_class.register!(fake_app_class, backend:)

    expect(Kaal.configuration.backend).to eq(backend)
  end

  it 'loads scheduler files with fallback environment detection' do
    Dir.mktmpdir('kaal-sinatra-load-') do |root|
      FileUtils.mkdir_p(File.join(root, 'config'))
      File.write(
        File.join(root, 'config', 'scheduler.yml'),
        YAML.dump(
          'defaults' => {
            'jobs' => [
              {
                'key' => 'sinatra:load',
                'cron' => '* * * * *',
                'job_class' => 'KaalSinatraLoadJob',
                'enabled' => true
              }
            ]
          }
        )
      )

      stub_const('KaalSinatraLoadJob', Class.new do
        def self.perform(*); end
      end)

      original_rack_env = ENV.fetch('RACK_ENV', nil)
      ENV['RACK_ENV'] = 'test'
      described_class.load_scheduler_file!(root:, environment: nil)

      expect(Kaal.registered?(key: 'sinatra:load')).to be(true)
    ensure
      ENV['RACK_ENV'] = original_rack_env
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
    expect(described_class.send(:root_path_for, plain_app)).to eq(Pathname.new(Dir.pwd))
    expect(described_class.send(:environment_name_for, plain_app)).to eq('development')
    expect(described_class.send(:settings_for, plain_app)).to eq(plain_app)
  end

  it 'installs a shutdown hook only when managed startup is requested' do
    Dir.mktmpdir('kaal-sinatra-start-') do |root|
      fake_app_class.root = root
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
    Dir.mktmpdir('kaal-sinatra-running-') do |root|
      fake_app_class.root = root
      FileUtils.mkdir_p(File.join(root, 'config'))
      File.write(File.join(root, 'config', 'scheduler.yml'), YAML.dump('defaults' => { 'jobs' => [] }))

      allow(described_class).to receive(:install_shutdown_hook)
      allow(Kaal).to receive_messages(start!: nil, running?: true)

      described_class.register!(fake_app_class, start_scheduler: true)

      expect(Kaal).not_to have_received(:start!)
      expect(described_class).not_to have_received(:install_shutdown_hook)
    end
  end

  it 'extends Sinatra apps with the kaal DSL' do
    app = Class.new
    database = Sequel.sqlite

    described_class::Extension.registered(app)
    expect(app).to respond_to(:kaal)

    allow(described_class).to receive(:register!).with(app, database:)
    app.kaal(database:)

    expect(described_class).to have_received(:register!).with(app, database:)
  ensure
    database&.disconnect
  end

  it 'avoids duplicate shutdown hook registration and swallows stop errors in the managed hook' do
    described_class.instance_variable_set(:@shutdown_hook_installed, nil)
    logger = instance_double(Logger, error: nil)
    Kaal.configuration.logger = logger

    allow(Kernel).to receive(:at_exit).and_yield
    allow(Kaal).to receive(:running?).and_return(true)
    allow(described_class).to receive(:stop!).and_raise(StandardError, 'stop failure')

    expect { described_class.send(:install_shutdown_hook) }.not_to raise_error
    expect { described_class.send(:install_shutdown_hook) }.not_to raise_error
    expect(Kernel).to have_received(:at_exit).once
    expect(logger).to have_received(:error).with(/Failed to stop Kaal during Sinatra shutdown: stop failure/)
  ensure
    described_class.instance_variable_set(:@shutdown_hook_installed, nil)
  end

  it 'swallows managed shutdown stop errors when no logger is configured' do
    described_class.instance_variable_set(:@shutdown_hook_installed, nil)
    Kaal.configuration.logger = nil

    allow(Kernel).to receive(:at_exit).and_yield
    allow(Kaal).to receive(:running?).and_return(true)
    allow(described_class).to receive(:stop!).and_raise(StandardError, 'stop failure')

    expect { described_class.send(:install_shutdown_hook) }.not_to raise_error
  ensure
    described_class.instance_variable_set(:@shutdown_hook_installed, nil)
  end

  it 'skips the managed shutdown hook body when the scheduler is not running' do
    described_class.instance_variable_set(:@shutdown_hook_installed, nil)

    allow(Kernel).to receive(:at_exit).and_yield
    allow(Kaal).to receive(:running?).and_return(false)
    allow(described_class).to receive(:stop!)

    described_class.send(:install_shutdown_hook)

    expect(described_class).not_to have_received(:stop!)
  ensure
    described_class.instance_variable_set(:@shutdown_hook_installed, nil)
  end
end
