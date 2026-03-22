# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'open3'
require 'pathname'
require 'fileutils'
require 'sequel'
require 'tmpdir'
require 'uri'

module KaalSinatraDummyAppSupport
  module_function

  GEM_ROOT = File.expand_path('../..', __dir__)
  DUMMY_SOURCE = File.join(GEM_ROOT, 'spec', 'dummy')

  def with_dummy_app(type)
    Dir.mktmpdir("kaal-sinatra-#{type}-") do |root|
      app_root = File.join(root, type.to_s)
      FileUtils.copy_entry(File.join(DUMMY_SOURCE, type.to_s), app_root)
      FileUtils.mkdir_p(File.join(app_root, 'db'))
      FileUtils.mkdir_p(File.join(app_root, 'tmp'))
      yield app_root, default_env(app_root)
    end
  end

  def run!(app_root, env, code)
    stdout, stderr, status = Open3.capture3(normalized_env(env), 'bundle', 'exec', 'ruby', '-e', code, chdir: app_root)
    return stdout if status.success?

    raise <<~ERROR
      Command failed: bundle exec ruby -e #{code.inspect}
      stdout:
      #{stdout}
      stderr:
      #{stderr}
    ERROR
  end

  def database_path(app_root)
    File.join(app_root, 'db', 'kaal.sqlite3')
  end

  def job_log_path(app_root)
    File.join(app_root, 'tmp', 'job.log')
  end

  def default_env(app_root)
    {
      'BUNDLE_GEMFILE' => File.join(GEM_ROOT, 'Gemfile'),
      'JOB_LOG_PATH' => job_log_path(app_root),
      'KAAL_SINATRA_LIB_PATH' => File.join(GEM_ROOT, 'lib'),
      'RACK_ENV' => 'test'
    }
  end

  def normalized_env(env)
    bundle_gemfile = env.fetch('BUNDLE_GEMFILE')
    env.merge('BUNDLE_GEMFILE' => absolute_path(bundle_gemfile))
  end

  def prepare_database!(backend, database_url:, app_root:)
    case backend
    when 'sqlite'
      prepare_sqlite_database!(app_root)
    when 'postgres', 'mysql'
      reset_database!(database_url)
      database = Sequel.connect(database_url)
      create_sql_schema(database, backend)
    else
      raise ArgumentError, "Unsupported SQL backend: #{backend.inspect}"
    end
  ensure
    database&.disconnect
  end

  def prepare_sqlite_database!(app_root)
    database = Sequel.sqlite(database_path(app_root))
    create_sql_schema(database, 'sqlite')
  ensure
    database&.disconnect
  end

  def create_sql_schema(database, backend)
    database.create_table?(:kaal_dispatches) do
      primary_key :id
      String :key, null: false
      Time :fire_time, null: false
      Time :dispatched_at, null: false
      String :node_id, null: false
      String :status, null: false, default: 'dispatched', size: 50
      index %i[key fire_time], unique: true
      index :key
      index :node_id
      index :status
      index :fire_time
    end

    if backend == 'sqlite'
      database.create_table?(:kaal_locks) do
        primary_key :id
        String :key, null: false
        Time :acquired_at, null: false
        Time :expires_at, null: false
        index :key, unique: true
        index :expires_at
      end
    end

    database.create_table?(:kaal_definitions) do
      primary_key :id
      String :key, null: false
      String :cron, null: false
      TrueClass :enabled, null: false, default: true
      String :source, null: false
      String :metadata, text: true, null: false, default: '{}'
      Time :disabled_at
      Time :created_at, null: false
      Time :updated_at, null: false
      index :key, unique: true
      index :enabled
      index :source
    end
  end

  def reset_database!(database_url, env: ENV)
    uri = URI.parse(database_url)
    ensure_safe_database_reset!(uri.path.delete_prefix('/'), env:)

    case uri.scheme
    when 'postgres', 'postgresql'
      reset_postgres_database!(uri)
    when 'mysql2'
      reset_mysql_database!(uri)
    else
      raise ArgumentError, "Unsupported database URL for reset: #{database_url.inspect}"
    end
  end

  def ensure_safe_database_reset!(database_name, env: ENV)
    return if env['KAAL_ALLOW_DATABASE_RESET'] == '1'
    return if test_database_name?(database_name)

    raise ArgumentError,
          "Refusing to reset non-test database #{database_name.inspect}; set KAAL_ALLOW_DATABASE_RESET=1 to override"
  end

  def test_database_name?(database_name)
    database_name.to_s.downcase.match?(/(?:\A|[_-])(test|spec)(?:[_-]|\z)/)
  end

  def reset_postgres_database!(uri)
    require 'pg'

    database_name = uri.path.delete_prefix('/')
    admin_connection = PG.connect(
      host: uri.host,
      port: uri.port || 5432,
      user: uri.user,
      password: uri.password,
      dbname: 'postgres'
    )

    admin_connection.exec_params(
      'SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = $1 AND pid <> pg_backend_pid()',
      [database_name]
    )
    admin_connection.exec("DROP DATABASE IF EXISTS #{PG::Connection.quote_ident(database_name)}")
    admin_connection.exec("CREATE DATABASE #{PG::Connection.quote_ident(database_name)}")
  ensure
    admin_connection&.close
  end

  def reset_mysql_database!(uri)
    require 'mysql2'

    database_name = uri.path.delete_prefix('/')
    admin_connection = Mysql2::Client.new(
      host: uri.host,
      port: uri.port || 3306,
      username: uri.user,
      password: uri.password
    )

    safe_database_name = database_name.delete('`')
    admin_connection.query("DROP DATABASE IF EXISTS `#{safe_database_name}`")
    admin_connection.query("CREATE DATABASE `#{safe_database_name}`")
  ensure
    admin_connection&.close
  end

  def absolute_path(path)
    return path if Pathname.new(path).absolute?

    File.expand_path(path, GEM_ROOT)
  end
end
