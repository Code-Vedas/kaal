# frozen_string_literal: true

require 'thor'
require 'fileutils'
require 'fugit'
require 'kaal'

module Kaal
  # Thor-powered CLI for plain-Ruby usage.
  class CLI < Thor
    # Internal instance helpers excluded from the public Thor command surface.
    module Helpers
      private

      def load_project!
        Kaal.reset_configuration!
        Kaal.reset_registry!
        load config_path
        runtime_context = RuntimeContext.default(root_path: root_path)
        Kaal.load_scheduler_file!(runtime_context: runtime_context) if File.exist?(scheduler_path)
      end

      def root_path
        File.expand_path(options[:root])
      end

      def config_path
        config = options[:config]
        return File.expand_path(config) if config

        File.join(root_path, 'config', 'kaal.rb')
      end

      def scheduler_path
        File.join(root_path, 'config', 'scheduler.yml')
      end

      def render_config_template(backend)
        case backend
        when 'memory'
          <<~RUBY
            require 'kaal'

            Kaal.configure do |config|
              config.backend = Kaal::Backend::MemoryAdapter.new
              config.tick_interval = 5
              config.window_lookback = 120
              config.lease_ttl = 125
              config.scheduler_config_path = 'config/scheduler.yml'
            end
          RUBY
        when 'redis'
          <<~RUBY
            require 'kaal'
            require 'redis'

            redis = Redis.new(url: ENV.fetch('REDIS_URL'))

            Kaal.configure do |config|
              config.backend = Kaal::Backend::RedisAdapter.new(redis, namespace: 'kaal')
              config.tick_interval = 5
              config.window_lookback = 120
              config.lease_ttl = 125
              config.scheduler_config_path = 'config/scheduler.yml'
            end
          RUBY
        else
          raise Thor::Error, "Unsupported backend '#{backend}'"
        end
      end

      def scheduler_template
        <<~YAML
          defaults:
            jobs:
              - key: "example:heartbeat"
                cron: "*/5 * * * *"
                job_class: "ExampleHeartbeatJob"
                enabled: true
                args:
                  - "{{fire_time.iso8601}}"
                kwargs:
                  idempotency_key: "{{idempotency_key}}"
                metadata:
                  owner: "ops"
        YAML
      end
    end

    package_name 'kaal'

    class_option :root, type: :string, default: Dir.pwd, desc: 'Project root'
    class_option :config, type: :string, desc: 'Path to config/kaal.rb'

    desc 'init', 'Generate config/kaal.rb and config/scheduler.yml'
    option :backend, type: :string, default: 'memory', enum: %w[memory redis]
    def init
      root = File.expand_path(options[:root])
      backend = options[:backend]
      writer = self.class
      FileUtils.mkdir_p(File.join(root, 'config'))

      writer.write_file(File.join(root, 'config', 'kaal.rb'), render_config_template(backend))
      writer.write_file(File.join(root, 'config', 'scheduler.yml'), scheduler_template)

      say("Initialized Kaal project for #{backend} backend")
    end

    desc 'start', 'Start the scheduler loop in the foreground'
    def start
      load_project!

      signal_state = {
        graceful_shutdown_started: false,
        shutdown_complete: false,
        force_exit_requested: false
      }
      previous_handlers = Kaal::CLI.install_foreground_signal_handlers(signal_state)

      begin
        thread = Kaal.start!
        raise Thor::Error, 'scheduler is already running' unless thread

        say('Kaal scheduler started in foreground')
        thread.join
      rescue Interrupt
        raise Thor::Error, 'shutdown timed out; forced exit requested' if signal_state[:force_exit_requested]

        Kaal::CLI.shutdown_scheduler(signal: 'INT', signal_state: signal_state, shell: shell)
      ensure
        Kaal::CLI.restore_signal_handlers(previous_handlers)
      end
    end

    desc 'status', 'Show scheduler status and registered jobs'
    def status
      load_project!
      registered = Kaal.registered
      say("Kaal v#{Kaal::VERSION}")
      say("Running: #{Kaal.running?}")
      say("Tick interval: #{Kaal.tick_interval}s")
      say("Window lookback: #{Kaal.window_lookback}s")
      say("Window lookahead: #{Kaal.window_lookahead}s")
      say("Lease TTL: #{Kaal.lease_ttl}s")
      say("Namespace: #{Kaal.namespace}")
      say("Registered jobs: #{registered.length}")
      registered.each { |entry| say("  - #{entry.key} (#{entry.cron})") }
    end

    desc 'tick', 'Run a single scheduler tick'
    def tick
      load_project!
      Kaal.tick!
      say('Kaal tick completed')
    end

    desc 'explain EXPRESSION', 'Humanize a cron expression'
    def explain(expression)
      say(Kaal.to_human(expression))
    end

    desc 'next EXPRESSION', 'Print upcoming fire times'
    option :count, type: :numeric, default: 5
    def next(expression)
      cron = Fugit.parse_cron(expression)
      raise Thor::Error, "Invalid cron expression: #{expression}" unless cron

      current = Time.now.utc
      options[:count].to_i.times do
        current = cron.next_time(current).to_t.utc
        say(current.iso8601)
      end
    end

    def self.exit_on_failure?
      true
    end

    def self.write_file(path, contents)
      return if File.exist?(path)

      File.write(path, contents)
    end

    def self.install_foreground_signal_handlers(signal_state)
      installer = SignalHandlerInstaller.new
      installer.install do |signal, previous_handler|
        shutdown_scheduler(signal: signal, signal_state: signal_state, previous_handler: previous_handler)
      end
    end

    def self.restore_signal_handlers(previous_handlers)
      previous_handlers.each do |signal, handler|
        Signal.trap(signal, handler)
      rescue StandardError
        nil
      end
    end

    def self.shutdown_scheduler(signal:, signal_state:, previous_handler: nil, shell: nil)
      shell_instance = shell || Thor::Base.shell.new
      return if signal_state[:shutdown_complete]

      if signal_state[:graceful_shutdown_started]
        signal_state[:force_exit_requested] = true
        shell_instance.warn("Received #{signal} again; forcing scheduler shutdown")
        Thread.main.raise(Interrupt)
        return
      end

      signal_state[:graceful_shutdown_started] = true
      shell_instance.say("Received #{signal}, stopping Kaal scheduler...")
      stopped = Kaal.stop!(timeout: 30)
      if stopped
        signal_state[:shutdown_complete] = true
        shell_instance.say('Kaal scheduler stopped')
      else
        shell_instance.warn('Kaal scheduler stop timed out; send TERM/INT again to force exit')
      end
    ensure
      SignalHandlerChain.new(signal: signal, previous_handler: previous_handler, logger: Kaal.logger).call(signal)
    end

    no_commands { include Helpers }
  end
end
