# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'cgi'
require 'uri'
require 'yaml'

module KaalIntegrationSupport
  module_function

  def reset_job_calls!
    RecorderJob.calls.clear
  end

  def runtime_context(root)
    Kaal::RuntimeContext.new(root_path: root, environment_name: 'test')
  end

  def with_project_root(prefix)
    root = Dir.mktmpdir("kaal-e2e-#{prefix}-")
    FileUtils.mkdir_p(File.join(root, 'config'))
    yield root
  ensure
    FileUtils.remove_entry(root) if root && File.exist?(root)
  end

  def namespace(prefix)
    "kaal-e2e-#{prefix}-#{Process.pid}-#{Time.now.to_i}"
  end

  def write_scheduler(root, key: 'integration:heartbeat', job_class_name: 'KaalIntegrationSupport::RecorderJob')
    scheduler = {
      'defaults' => {
        'jobs' => [
          {
            'key' => key,
            'cron' => '* * * * *',
            'job_class' => job_class_name,
            'enabled' => true,
            'args' => ['{{fire_time.iso8601}}'],
            'kwargs' => {
              'idempotency_key' => '{{idempotency_key}}'
            }
          }
        ]
      }
    }

    File.write(File.join(root, 'config', 'scheduler.yml'), YAML.dump(scheduler))
  end

  def write_config(root, body)
    File.write(File.join(root, 'config', 'kaal.rb'), body)
  end

  def perform_tick_flow(root, key:)
    reset_job_calls!
    load File.join(root, 'config', 'kaal.rb')
    Kaal.load_scheduler_file!(runtime_context: runtime_context(root))
    raise "scheduler key #{key} was not registered" unless Kaal.registered?(key: key)

    Kaal.tick!
    first_pass_calls = RecorderJob.calls.map(&:dup)
    raise 'expected at least one dispatched job' if first_pass_calls.empty?

    first_pass_calls
  end

  def create_sqlite_schema(database)
    create_sql_schema(database, locks: true)
  end

  def create_pg_mysql_schema(database)
    create_sql_schema(database, locks: false)
  end

  def reset_database!(database_url)
    connection_info = parse_database_url(database_url)
    database_name = connection_info.fetch(:database)

    raise ArgumentError, "Unsupported database name: #{database_name.inspect}" unless database_name.match?(/\A[a-zA-Z0-9_]+\z/)

    admin_database = Sequel.connect(connection_info.fetch(:admin_url))

    case connection_info.fetch(:adapter)
    when 'postgres', 'postgresql'
      admin_database.disconnect
      terminate_postgres_connections!(connection_info:, database_name:)
      admin_database = Sequel.connect(connection_info.fetch(:admin_url))
      admin_database.run("DROP DATABASE IF EXISTS #{database_name}")
      admin_database.run("CREATE DATABASE #{database_name}")
    when 'mysql2'
      admin_database.run("DROP DATABASE IF EXISTS `#{database_name}`")
      admin_database.run("CREATE DATABASE `#{database_name}`")
    else
      raise ArgumentError, "Unsupported adapter: #{connection_info.fetch(:adapter)}"
    end
  ensure
    admin_database&.disconnect
  end

  def create_sql_schema(database, locks:)
    database.drop_table?(:kaal_locks, :kaal_dispatches, :kaal_definitions)

    create_dispatches_table(database)
    create_locks_table(database) if locks
    create_definitions_table(database)
  end

  def create_dispatches_table(database)
    database.create_table :kaal_dispatches do
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
  end

  def create_locks_table(database)
    database.create_table :kaal_locks do
      primary_key :id
      String :key, null: false
      Time :acquired_at, null: false
      Time :expires_at, null: false
      index :key, unique: true
      index :expires_at
    end
  end

  def create_definitions_table(database)
    database.create_table :kaal_definitions do
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

  def terminate_postgres_connections!(connection_info:, database_name:)
    admin_database = Sequel.connect(connection_info.fetch(:admin_url))
    quoted_database_name = admin_database.literal(database_name)

    admin_database.run(<<~SQL)
      SELECT pg_terminate_backend(pid)
      FROM pg_stat_activity
      WHERE datname = #{quoted_database_name}
        AND pid <> pg_backend_pid()
    SQL
  ensure
    admin_database&.disconnect
  end

  def parse_database_url(database_url)
    normalized_url = database_url.gsub('\\!', '!')
    uri = URI.parse(normalized_url)
    database_name = uri.path.delete_prefix('/')

    {
      adapter: uri.scheme,
      database: database_name,
      admin_url: build_admin_database_url(uri)
    }
  end

  def build_admin_database_url(uri)
    admin_database_name = uri.scheme.start_with?('postgres') ? 'postgres' : nil
    path = admin_database_name ? "/#{admin_database_name}" : nil

    admin_uri = URI::Generic.build(
      scheme: uri.scheme,
      userinfo: uri.userinfo,
      host: uri.host,
      port: uri.port,
      path: path,
      query: uri.query
    )

    admin_uri.to_s
  end

  class RedisClientWrapper
    def initialize(redis)
      @redis = redis
    end

    def set(key, value, **options)
      arguments = [key, value]
      arguments.push('NX') if options[:nx]
      arguments.push('PX', options[:px]) if options[:px]
      @redis.call('SET', *arguments)
    end

    def eval(*, **)
      @redis.eval(*, **)
    end

    def method_missing(method_name, ...)
      @redis.public_send(method_name, ...)
    end

    def respond_to_missing?(method_name, include_private = false)
      @redis.respond_to?(method_name, include_private) || super
    end
  end

  class RecorderJob
    def self.calls
      @calls ||= []
    end

    def self.perform(*args, **kwargs)
      calls << { args: args, kwargs: kwargs }
    end
  end
end
