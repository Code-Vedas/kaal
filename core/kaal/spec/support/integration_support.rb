# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
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
