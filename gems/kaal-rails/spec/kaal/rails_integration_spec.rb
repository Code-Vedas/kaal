# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Kaal::Rails do
  def runner_output(app_root, env, code)
    KaalRailsDummyAppSupport.run!(app_root, env, 'bin/rails', 'runner', code)
  end

  context 'with explicit memory override', integration: :memory do
    it 'boots the dummy app with a memory backend override' do
      KaalRailsDummyAppSupport.with_dummy_app do |app_root, env|
        output = runner_output(app_root, env.merge('KAAL_TEST_BACKEND' => 'memory'), 'puts Kaal.configuration.backend.class.name')
        expect(output.strip).to eq('Kaal::Backend::MemoryAdapter')
      end
    end
  end

  context 'with explicit redis override', integration: :redis do
    it 'boots the dummy app with a redis backend override' do
      KaalRailsDummyAppSupport.with_dummy_app do |app_root, env|
        output = runner_output(
          app_root,
          env.merge('KAAL_TEST_BACKEND' => 'redis', 'REDIS_URL' => ENV.fetch('REDIS_URL')),
          'puts Kaal.configuration.backend.class.name'
        )
        expect(output.strip).to eq('Kaal::Backend::RedisAdapter')
      end
    end
  end

  context 'with sqlite', integration: :sqlite do
    it 'auto-wires the backend, exposes tasks, generates files, and migrates' do
      KaalRailsDummyAppSupport.with_dummy_app do |app_root, env|
        task_output = KaalRailsDummyAppSupport.run!(app_root, env, 'bin/rake', '-T', 'kaal')
        expect(task_output).to include('kaal:install:all', 'kaal:install:migrations')

        KaalRailsDummyAppSupport.run!(app_root, env, 'bin/rails', 'generate', 'kaal:install', '--backend=sqlite')
        expect(File).to exist(File.join(app_root, 'config', 'scheduler.yml'))
        expect(KaalRailsDummyAppSupport.migration_slugs(app_root)).to eq(
          %w[create_kaal_definitions.rb create_kaal_dispatches.rb create_kaal_locks.rb]
        )

        KaalRailsDummyAppSupport.run!(app_root, env, 'bin/rails', 'db:migrate')
        output = runner_output(
          app_root,
          env,
          [
            'puts Kaal.configuration.backend.class.name',
            "puts [ActiveRecord::Base.connection.data_source_exists?('kaal_definitions'),",
            "      ActiveRecord::Base.connection.data_source_exists?('kaal_dispatches'),",
            "      ActiveRecord::Base.connection.data_source_exists?('kaal_locks')].join(',')"
          ].join("\n")
        )
        lines = output.lines.map(&:strip)

        expect(lines[0]).to eq('Kaal::ActiveRecord::DatabaseAdapter')
        expect(lines[1]).to eq('true,true,true')
      end
    end
  end

  context 'with postgres', integration: :pg do
    it 'auto-wires the backend and installs migrations through rake' do
      skip 'DATABASE_URL not set' if ENV['DATABASE_URL'].to_s.empty?

      KaalRailsDummyAppSupport.with_dummy_app do |app_root, env|
        pg_env = env.merge('DATABASE_URL' => ENV.fetch('DATABASE_URL'))
        KaalRailsDummyAppSupport.reset_database!(pg_env.fetch('DATABASE_URL'))
        KaalRailsDummyAppSupport.run!(app_root, pg_env, 'bin/rake', 'kaal:install:migrations')
        expect(KaalRailsDummyAppSupport.migration_slugs(app_root)).to eq(
          %w[create_kaal_definitions.rb create_kaal_dispatches.rb]
        )

        KaalRailsDummyAppSupport.run!(app_root, pg_env, 'bin/rails', 'db:migrate')
        output = runner_output(
          app_root,
          pg_env,
          [
            'puts Kaal.configuration.backend.class.name',
            "puts [ActiveRecord::Base.connection.data_source_exists?('kaal_definitions'),",
            "      ActiveRecord::Base.connection.data_source_exists?('kaal_dispatches')].join(',')"
          ].join("\n")
        )
        lines = output.lines.map(&:strip)

        expect(lines[0]).to eq('Kaal::ActiveRecord::PostgresAdapter')
        expect(lines[1]).to eq('true,true')
      end
    end
  end

  context 'with mysql', integration: :mysql do
    it 'auto-wires the backend and installs migrations through rake' do
      skip 'DATABASE_URL not set' if ENV['DATABASE_URL'].to_s.empty?

      KaalRailsDummyAppSupport.with_dummy_app do |app_root, env|
        mysql_env = env.merge('DATABASE_URL' => ENV.fetch('DATABASE_URL'))
        KaalRailsDummyAppSupport.reset_database!(mysql_env.fetch('DATABASE_URL'))
        KaalRailsDummyAppSupport.run!(app_root, mysql_env, 'bin/rake', 'kaal:install:migrations')
        expect(KaalRailsDummyAppSupport.migration_slugs(app_root)).to eq(
          %w[create_kaal_definitions.rb create_kaal_dispatches.rb]
        )

        KaalRailsDummyAppSupport.run!(app_root, mysql_env, 'bin/rails', 'db:migrate')
        output = runner_output(
          app_root,
          mysql_env,
          [
            'puts Kaal.configuration.backend.class.name',
            "puts [ActiveRecord::Base.connection.data_source_exists?('kaal_definitions'),",
            "      ActiveRecord::Base.connection.data_source_exists?('kaal_dispatches')].join(',')"
          ].join("\n")
        )
        lines = output.lines.map(&:strip)

        expect(lines[0]).to eq('Kaal::ActiveRecord::MySQLAdapter')
        expect(lines[1]).to eq('true,true')
      end
    end
  end
end
