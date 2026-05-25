# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'erb'
require 'yaml'

module Kaal
  module Config
    # Loads Kaal runtime configuration from config/kaal.yml and KAAL_* env vars.
    class FileLoader
      # Normalizes a single environment variable value into the requested config type.
      class EnvValue
        def initialize(value)
          @value = value.to_s.strip
        end

        def coerce(key:, env_name:)
          case key
          when :tick_interval, :window_lookback, :window_lookahead, :lease_ttl, :recovery_window, :recovery_startup_jitter
            coerce_integer(env_name)
          when :enable_log_dispatch_registry, :enable_dispatch_recovery
            coerce_boolean(env_name)
          when :scheduler_conflict_policy, :scheduler_missing_file_policy
            @value.to_sym
          when :delayed_job_allowed_class_prefixes
            @value.split(',').map(&:strip).reject(&:empty?)
          else
            @value
          end
        end

        private

        def coerce_boolean(env_name)
          normalized_value = @value.downcase
          return true if %w[1 true yes on].include?(normalized_value)
          return false if %w[0 false no off].include?(normalized_value)

          raise Kaal::ConfigurationError, "ENV #{env_name} must be a boolean"
        end

        def coerce_integer(env_name)
          raise Kaal::ConfigurationError, "ENV #{env_name} must be an integer" unless @value.match?(/\A-?\d+\z/)

          @value.to_i
        end
      end

      ENV_KEY_MAP = {
        'KAAL_BACKEND' => :backend,
        'KAAL_NAMESPACE' => :namespace,
        'KAAL_TICK_INTERVAL' => :tick_interval,
        'KAAL_WINDOW_LOOKBACK' => :window_lookback,
        'KAAL_WINDOW_LOOKAHEAD' => :window_lookahead,
        'KAAL_LEASE_TTL' => :lease_ttl,
        'KAAL_SCHEDULER_CONFIG_PATH' => :scheduler_config_path,
        'KAAL_ENABLE_LOG_DISPATCH_REGISTRY' => :enable_log_dispatch_registry,
        'KAAL_ENABLE_DISPATCH_RECOVERY' => :enable_dispatch_recovery,
        'KAAL_RECOVERY_WINDOW' => :recovery_window,
        'KAAL_RECOVERY_STARTUP_JITTER' => :recovery_startup_jitter,
        'KAAL_TIME_ZONE' => :time_zone,
        'KAAL_SCHEDULER_CONFLICT_POLICY' => :scheduler_conflict_policy,
        'KAAL_SCHEDULER_MISSING_FILE_POLICY' => :scheduler_missing_file_policy,
        'KAAL_DELAYED_JOB_ALLOWED_CLASS_PREFIXES' => :delayed_job_allowed_class_prefixes
      }.freeze
      CONFIG_KEY_TO_ENV_KEY = ENV_KEY_MAP.invert.freeze
      CONFIGURATION_ASSIGNERS = {
        namespace: ->(config, value) { config.namespace = value },
        tick_interval: ->(config, value) { config.tick_interval = value },
        window_lookback: ->(config, value) { config.window_lookback = value },
        window_lookahead: ->(config, value) { config.window_lookahead = value },
        lease_ttl: ->(config, value) { config.lease_ttl = value },
        scheduler_config_path: ->(config, value) { config.scheduler_config_path = value },
        enable_log_dispatch_registry: ->(config, value) { config.enable_log_dispatch_registry = value },
        enable_dispatch_recovery: ->(config, value) { config.enable_dispatch_recovery = value },
        recovery_window: ->(config, value) { config.recovery_window = value },
        recovery_startup_jitter: ->(config, value) { config.recovery_startup_jitter = value },
        time_zone: ->(config, value) { config.time_zone = value },
        scheduler_conflict_policy: ->(config, value) { config.scheduler_conflict_policy = value },
        scheduler_missing_file_policy: ->(config, value) { config.scheduler_missing_file_policy = value },
        delayed_job_allowed_class_prefixes: ->(config, value) { config.delayed_job_allowed_class_prefixes = value },
        logger: ->(config, value) { config.logger = value }
      }.freeze

      def initialize(configuration:, runtime_context:, env: ENV)
        @configuration = configuration
        @runtime_context = runtime_context
        @env = env
        @config_key_to_env_key = CONFIG_KEY_TO_ENV_KEY
      end

      def load(path: 'config/kaal.yml')
        absolute_path = @runtime_context.resolve_path(path)
        payload = File.exist?(absolute_path) ? parse_yaml(absolute_path) : {}
        merged = merge_environment_config(payload)
        merged = apply_env_overrides(merged)
        apply_configuration(merged)
        @configuration.validate!
        @configuration
      end

      private

      def parse_yaml(path)
        rendered = ERB.new(File.read(path), trim_mode: '-').result
        parsed = YAML.safe_load(rendered, aliases: true) || {}
        raise Kaal::ConfigurationError, "Expected Kaal config YAML root to be a mapping in #{path}" unless parsed.is_a?(Hash)

        Kaal::Support::HashTools.stringify_keys(parsed)
      rescue Psych::Exception => e
        raise Kaal::ConfigurationError, "Failed to parse Kaal config YAML at #{path}: #{e.message}"
      end

      def merge_environment_config(payload)
        defaults = hash_section(payload['defaults'])
        environment = hash_section(payload[@runtime_context.environment_name])

        Kaal::Support::HashTools.deep_merge(defaults, environment)
      end

      def hash_section(value)
        case value
        in Hash
          Kaal::Support::HashTools.stringify_keys(Kaal::Support::HashTools.deep_dup(value))
        in nil
          {}
        else
          raise Kaal::ConfigurationError, 'Kaal config sections must be mappings'
        end
      end

      def apply_env_overrides(config)
        merged = Kaal::Support::HashTools.deep_dup(config)

        ENV_KEY_MAP.each do |env_key, config_key|
          next unless @env.key?(env_key)

          merged[config_key.to_s] = coerce_env_value(config_key, @env.fetch(env_key))
        end

        backend_url = @env['KAAL_BACKEND_URL']
        if backend_url
          backend_config = hash_section(merged['backend_config'])
          if backend_config.key?('connection')
            backend_config['connection'] = backend_url
          else
            backend_config['url'] = backend_url
          end
          merged['backend_config'] = backend_config
        end

        merged
      end

      def coerce_env_value(key, value)
        EnvValue.new(value).coerce(key:, env_name: @config_key_to_env_key.fetch(key))
      end

      def apply_configuration(config)
        normalized = Kaal::Support::HashTools.symbolize_keys(config)
        backend_config = normalized.delete(:backend_config) || {}
        backend_name = normalized.delete(:backend)
        @configuration.apply_backend_runtime_context(@runtime_context)

        normalized.each do |key, value|
          apply_configuration_value(key, value)
        end

        @configuration.backend_config = backend_config
        @configuration.backend = backend_name if backend_name
      end

      def apply_configuration_value(key, value)
        CONFIGURATION_ASSIGNERS[key]&.call(@configuration, value)
      end
    end
  end
end
