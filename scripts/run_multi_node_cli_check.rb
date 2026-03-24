#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'sequel'
require 'redis'
require 'time'
require 'timeout'
require 'uri'
require 'yaml'

class MultiNodeCliCheck
  DEFAULT_POSTGRES_URL = 'postgres://postgres:postgres@localhost:5432/kaal_test_auto'
  DEFAULT_MYSQL_URL = 'mysql2://root:rootROOT!1@127.0.0.1:3306/kaal_test_auto'
  DEFAULT_REDIS_URL = 'redis://127.0.0.1:6379/0'

  def initialize(backend)
    @backend = backend
    @repo_root = File.expand_path('..', __dir__)
    @bundle_root = File.join(@repo_root, 'core', 'kaal-sequel')
    @project_root = File.join(@repo_root, 'tmp', 'multi_node_cli', backend)
    @log_dir = File.join(@project_root, 'logs')
    @namespace = "kaal-multi-node-cli-#{backend}-#{Process.pid}-#{Time.now.to_i}"
    @target_time = next_target_time
    @runs_key = "#{@namespace}:job_runs"
    @child_pids = []
  end

  def call
    validate_backend!
    prepare_project_root
    prepare_backend_state
    write_runtime_project
    start_nodes
    wait_for_schedule_window
    verify_single_run!
    puts success_summary
  ensure
    stop_nodes
  end

  private

  attr_reader :backend, :repo_root, :bundle_root, :project_root, :log_dir, :namespace, :target_time, :runs_key, :child_pids

  def validate_backend!
    return if %w[redis postgres mysql].include?(backend)

    raise ArgumentError, "unsupported backend #{backend.inspect}"
  end

  def prepare_project_root
    FileUtils.rm_rf(project_root)
    FileUtils.mkdir_p([
      File.join(project_root, 'config'),
      File.join(project_root, 'lib'),
      log_dir
    ])
  end

  def prepare_backend_state
    case backend
    when 'redis'
      prepare_redis_state
    when 'postgres', 'mysql'
      reset_database!
      create_sql_schema!
    end
  end

  def write_runtime_project
    File.write(File.join(project_root, 'config', 'scheduler.yml'), YAML.dump(scheduler_config))
    File.write(File.join(project_root, 'config', 'kaal.rb'), config_rb)
    File.write(File.join(project_root, 'lib', 'multi_node_recording_job.rb'), job_rb)
  end

  def start_nodes
    2.times do |index|
      log_file = File.join(log_dir, "node-#{index + 1}.log")
      pid = Process.spawn(
        env_for_process,
        'bundle', 'exec', 'kaal', 'start', '--root', project_root,
        chdir: bundle_root,
        out: log_file,
        err: log_file
      )
      child_pids << pid
      sleep 3
      assert_nodes_running!
    end
  end

  def assert_nodes_running!
    child_pids.each do |pid|
      next unless Process.wait(pid, Process::WNOHANG)

      raise "scheduler node #{pid} exited before the schedule window"
    rescue Errno::ECHILD
      raise "scheduler node #{pid} exited before the schedule window"
    end
  end

  def wait_for_schedule_window
    sleep_seconds = [(target_time + 15) - Time.now.utc, 0].max
    sleep(sleep_seconds)
  end

  def verify_single_run!
    count = run_count
    return if count == 1

    raise "expected exactly one job run for #{backend}, got #{count} (#{diagnostics})"
  end

  def success_summary
    {
      backend: backend,
      target_time: target_time.iso8601,
      namespace: namespace,
      runs: run_count
    }.to_json
  end

  def stop_nodes
    child_pids.each do |pid|
      begin
        Process.kill('KILL', pid)
      rescue Errno::ESRCH
        next
      end
    end

    child_pids.each do |pid|
      begin
        Timeout.timeout(10) { Process.wait(pid) }
      rescue Errno::ECHILD, Timeout::Error
        begin
          Process.kill('KILL', pid)
        rescue Errno::ESRCH
          nil
        end
      end
    end
  ensure
    print_logs_on_failure if $ERROR_INFO
  end

  def print_logs_on_failure
    Dir.glob(File.join(log_dir, '*.log')).sort.each do |log_file|
      warn "== #{File.basename(log_file)} =="
      warn File.read(log_file)
    end
  end

  def scheduler_config
    {
      'defaults' => {
        'jobs' => [
          {
            'key' => "multi-node:#{backend}",
            'cron' => target_cron,
            'job_class' => 'MultiNodeRecordingJob',
            'enabled' => true,
            'args' => ['{{fire_time.iso8601}}'],
            'kwargs' => {
              'idempotency_key' => '{{idempotency_key}}'
            }
          }
        ]
      }
    }
  end

  def target_cron
    [
      target_time.min,
      target_time.hour,
      target_time.day,
      target_time.month,
      '*'
    ].join(' ')
  end

  def config_rb
    <<~RUBY
      require 'kaal/sequel'
      require 'redis'
      require_relative '../lib/multi_node_recording_job'

      backend_name = ENV.fetch('KAAL_MULTI_NODE_BACKEND')
      namespace = ENV.fetch('KAAL_MULTI_NODE_NAMESPACE')

      backend = case backend_name
      when 'redis'
        redis = Redis.new(url: ENV.fetch('KAAL_MULTI_NODE_REDIS_URL'))
        Kaal::Backend::RedisAdapter.new(redis, namespace: namespace)
      when 'postgres'
        database = Sequel.connect(ENV.fetch('KAAL_MULTI_NODE_DATABASE_URL'))
        Kaal::Backend::PostgresAdapter.new(database)
      when 'mysql'
        database = Sequel.connect(ENV.fetch('KAAL_MULTI_NODE_DATABASE_URL'))
        Kaal::Backend::MySQLAdapter.new(database)
      else
        raise "Unsupported backend: \#{backend_name}"
      end

      Kaal.configure do |config|
        config.backend = backend
        config.namespace = namespace
        config.tick_interval = 1
        config.window_lookback = 65
        config.window_lookahead = 0
        config.lease_ttl = 66
        config.enable_log_dispatch_registry = true
        config.enable_dispatch_recovery = false
        config.recovery_startup_jitter = 0
        config.scheduler_config_path = 'config/scheduler.yml'
      end
    RUBY
  end

  def job_rb
    <<~RUBY
      require 'json'
      require 'redis'
      require 'sequel'
      require 'time'

      class MultiNodeRecordingJob
        def self.perform(fire_time_iso8601, idempotency_key:)
          case ENV.fetch('KAAL_MULTI_NODE_BACKEND')
          when 'redis'
            record_redis_run(fire_time_iso8601:, idempotency_key:)
          when 'postgres', 'mysql'
            record_sql_run(fire_time_iso8601:, idempotency_key:)
          else
            raise "Unsupported backend: \#{ENV.fetch('KAAL_MULTI_NODE_BACKEND')}"
          end
        end

        def self.record_redis_run(fire_time_iso8601:, idempotency_key:)
          redis = Redis.new(url: ENV.fetch('KAAL_MULTI_NODE_REDIS_URL'))
          payload = JSON.generate(
            fire_time: fire_time_iso8601,
            idempotency_key: idempotency_key,
            pid: Process.pid
          )
          redis.rpush(ENV.fetch('KAAL_MULTI_NODE_RUNS_KEY'), payload)
        ensure
          redis&.close
        end

        def self.record_sql_run(fire_time_iso8601:, idempotency_key:)
          database = Sequel.connect(ENV.fetch('KAAL_MULTI_NODE_DATABASE_URL'))
          database[:job_runs].insert(
            fire_time: Time.iso8601(fire_time_iso8601),
            idempotency_key: idempotency_key,
            pid: Process.pid.to_s,
            created_at: Time.now.utc
          )
        ensure
          database&.disconnect
        end
      end
    RUBY
  end

  def env_for_process
    env = {
      'BUNDLE_GEMFILE' => File.join(bundle_root, 'Gemfile'),
      'KAAL_MULTI_NODE_BACKEND' => backend,
      'KAAL_MULTI_NODE_NAMESPACE' => namespace,
      'KAAL_MULTI_NODE_RUNS_KEY' => runs_key
    }

    case backend
    when 'redis'
      env['KAAL_MULTI_NODE_REDIS_URL'] = redis_url
    when 'postgres', 'mysql'
      env['KAAL_MULTI_NODE_DATABASE_URL'] = database_url
    end

    env
  end

  def next_target_time
    now = Time.now.utc
    target = Time.utc(now.year, now.month, now.day, now.hour, now.min) + 60
    target += 60 while (target - now) < 20
    target
  end

  def redis_url
    ENV.fetch('REDIS_URL', DEFAULT_REDIS_URL)
  end

  def database_url
    case backend
    when 'postgres'
      ENV.fetch('KAAL_MULTI_NODE_POSTGRES_URL', DEFAULT_POSTGRES_URL)
    when 'mysql'
      ENV.fetch('KAAL_MULTI_NODE_MYSQL_URL', DEFAULT_MYSQL_URL)
    else
      raise "No database URL for #{backend}"
    end
  end

  def run_count
    case backend
    when 'redis'
      redis_run_count
    when 'postgres', 'mysql'
      sql_run_count
    end
  end

  def prepare_redis_state
    redis = Redis.new(url: redis_url)
    redis.scan_each(match: "#{namespace}:*") { |key| redis.del(key) }
    redis.del(runs_key)
  ensure
    redis&.close
  end

  def redis_run_count
    redis = Redis.new(url: redis_url)
    redis.llen(runs_key)
  ensure
    redis&.close
  end

  def reset_database!
    connection_info = parse_database_url(database_url)
    database_name = connection_info.fetch(:database)
    admin_url = connection_info.fetch(:admin_url)

    admin_database = Sequel.connect(admin_url)

    case backend
    when 'postgres'
      admin_database.disconnect
      terminate_postgres_connections!(admin_url:, database_name:)
      admin_database = Sequel.connect(admin_url)
      admin_database.run("DROP DATABASE IF EXISTS #{database_name}")
      admin_database.run("CREATE DATABASE #{database_name}")
    when 'mysql'
      admin_database.run("DROP DATABASE IF EXISTS `#{database_name}`")
      admin_database.run("CREATE DATABASE `#{database_name}`")
    end
  ensure
    admin_database&.disconnect
  end

  def create_sql_schema!
    database = Sequel.connect(database_url)
    database.drop_table?(:job_runs, :kaal_dispatches, :kaal_definitions)

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

    database.create_table :job_runs do
      primary_key :id
      Time :fire_time, null: false
      String :idempotency_key, null: false
      String :pid, null: false
      Time :created_at, null: false
      index :fire_time
      index :idempotency_key
    end
  ensure
    database&.disconnect
  end

  def sql_run_count
    database = Sequel.connect(database_url)
    database[:job_runs].count
  ensure
    database&.disconnect
  end

  def diagnostics
    case backend
    when 'redis'
      redis_diagnostics
    when 'postgres', 'mysql'
      sql_diagnostics
    else
      'no diagnostics available'
    end
  end

  def redis_diagnostics
    redis = Redis.new(url: redis_url)
    payloads = redis.lrange(runs_key, 0, -1)
    "entries=#{payloads.inspect}"
  ensure
    redis&.close
  end

  def sql_diagnostics
    database = Sequel.connect(database_url)
    job_runs = database[:job_runs].order(:id).all
    dispatches = database[:kaal_dispatches].order(:id).all
    "job_runs=#{job_runs.inspect}, dispatches=#{dispatches.inspect}"
  ensure
    database&.disconnect
  end

  def terminate_postgres_connections!(admin_url:, database_name:)
    admin_database = Sequel.connect(admin_url)
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

  def parse_database_url(url)
    uri = URI.parse(url)
    database_name = uri.path.delete_prefix('/')

    {
      database: database_name,
      admin_url: build_admin_database_url(uri)
    }
  end

  def build_admin_database_url(uri)
    admin_database_name = backend == 'postgres' ? 'postgres' : nil
    path = admin_database_name ? "/#{admin_database_name}" : nil

    URI::Generic.build(
      scheme: uri.scheme,
      userinfo: uri.userinfo,
      host: uri.host,
      port: uri.port,
      path: path,
      query: uri.query
    ).to_s
  end
end

MultiNodeCliCheck.new(ARGV.fetch(0)).call
