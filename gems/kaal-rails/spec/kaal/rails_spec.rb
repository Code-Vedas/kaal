# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'rails_helper'
require 'rake'
require 'rails/generators'
require 'generators/kaal/install_generator'

RSpec.describe Kaal::Rails do
  def silence_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = original_stdout
  end

  around do |example|
    original_backend = Kaal.configuration.backend
    Kaal.configuration.backend = nil
    example.run
    Kaal.configuration.backend = original_backend
  end

  it 'has a version number and loads the railtie' do
    expect(described_class::VERSION).to eq('0.2.1')
    expect(described_class::Railtie).to be < Rails::Railtie
  end

  it 'detects supported database adapters and builds matching backends' do
    db_config = Struct.new(:adapter)

    expect(described_class.detect_backend_name(db_config.new('SQLite3'))).to eq('sqlite')
    expect(described_class.detect_backend_name(db_config.new('PostgreSQL'))).to eq('postgres')
    expect(described_class.detect_backend_name(db_config.new('Mysql2'))).to eq('mysql')
    expect(described_class.detect_backend_name(db_config.new('Trilogy'))).to eq('mysql')
    expect(described_class.detect_backend_name(db_config.new('Oracle'))).to be_nil
    expect(described_class.detect_backend_name(nil)).to be_nil

    expect(described_class.build_backend('sqlite')).to be_a(Kaal::ActiveRecord::DatabaseAdapter)
    expect(described_class.build_backend('postgres')).to be_a(Kaal::ActiveRecord::PostgresAdapter)
    expect(described_class.build_backend('mysql')).to be_a(Kaal::ActiveRecord::MySQLAdapter)
    expect(described_class.build_backend('unknown')).to be_nil
  end

  it 'auto-wires the Active Record backend and preserves explicit overrides' do
    Kaal.configuration.backend = nil
    expect(described_class.configure_backend!).to be_a(Kaal::ActiveRecord::DatabaseAdapter)
    expect(Kaal.configuration.backend).to be_a(Kaal::ActiveRecord::DatabaseAdapter)

    Kaal.configuration.backend = nil
    expect(described_class.configure_backend!(backend: nil)).to be_nil
    expect(Kaal.configuration.backend).to be_nil

    custom_backend = Kaal::Backend::MemoryAdapter.new
    Kaal.configuration.backend = custom_backend

    expect(described_class.configure_backend!).to eq(custom_backend)
    expect(Kaal.configuration.backend).to eq(custom_backend)
  end

  it 'installs scheduler config and migrations through the installer' do
    Dir.mktmpdir('kaal-rails-install-') do |root|
      FileUtils.mkdir_p(File.join(root, 'config'))

      result = described_class.install!(root:, backend: 'sqlite')
      second_result = described_class.install!(root:, backend: 'sqlite')

      expect(result.fetch(:scheduler_config).fetch(:status)).to eq(:create)
      expect(File).to exist(File.join(root, 'config', 'scheduler.yml'))
      expect(
        result.fetch(:migrations).map { |migration| File.basename(migration.fetch(:path)).sub(/^\d+_/, '') }.sort
      ).to eq(
        %w[create_kaal_definitions.rb create_kaal_dispatches.rb create_kaal_locks.rb]
      )
      expect(second_result.fetch(:scheduler_config).fetch(:status)).to eq(:identical)
      expect(second_result.fetch(:migrations).map { |migration| migration.fetch(:status) }).to all(eq(:identical))
      expect { described_class.install!(root:, backend: 'memory') }.to raise_error(ArgumentError, /Unsupported Rails datastore backend/)
    end
  end

  it 'registers rake tasks' do
    original_rake = Rake.application
    Rake.application = Rake::Application.new

    Rails.application.load_tasks

    expect(Rake::Task.task_defined?('kaal:install:all')).to be(true)
    expect(Rake::Task.task_defined?('kaal:install:migrations')).to be(true)
  ensure
    Rake.application = original_rake
  end

  it 'executes rake tasks through the railtie' do
    original_rake = Rake.application
    Rake.application = Rake::Application.new
    Rails.application.load_tasks

    install_results = {
      scheduler_config: { status: :create, path: '/tmp/config/scheduler.yml' },
      migrations: [{ status: :create, path: '/tmp/db/migrate/1_create_kaal_dispatches.rb' }]
    }
    installer = instance_double(Kaal::Rails::Installer, install_migrations: install_results.fetch(:migrations))

    allow(described_class).to receive_messages(install!: install_results, detect_backend_name: 'postgres')
    allow(Kaal::Rails::Installer).to receive(:new).and_return(installer)

    expect { Rake::Task['kaal:install:all'].invoke }.to output(
      "create /tmp/config/scheduler.yml\ncreate /tmp/db/migrate/1_create_kaal_dispatches.rb\n"
    ).to_stdout
    expect { Rake::Task['kaal:install:migrations'].invoke }.to output(
      "create /tmp/db/migrate/1_create_kaal_dispatches.rb\n"
    ).to_stdout
  ensure
    Rake.application = original_rake
  end

  it 'generates scheduler config and migration files through rails generators' do
    Dir.mktmpdir('kaal-rails-generator-') do |root|
      generator = Kaal::Generators::InstallGenerator.new([], { backend: 'postgres' }, destination_root: root)

      silence_stdout { generator.invoke_all }

      expect(File).to exist(File.join(root, 'config', 'scheduler.yml'))
      expect(Dir[File.join(root, 'db/migrate/*.rb')].map { |path| File.basename(path).sub(/^\d+_/, '') }.sort).to eq(
        %w[create_kaal_definitions.rb create_kaal_dispatches.rb]
      )
    end
  end
end
