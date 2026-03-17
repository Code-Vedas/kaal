# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'erb'
require 'yaml'

module Kaal
  class SchedulerFileLoader
    # Loads and validates scheduler YAML payloads from disk.
    class PayloadLoader
      def initialize(configuration:, runtime_context:, logger:, hash_transform:)
        @configuration = configuration
        @runtime_context = runtime_context
        @logger = logger
        @hash_transform = hash_transform
      end

      def load
        path = scheduler_file_path
        return [path, nil] unless File.exist?(path)

        [path, parse_yaml(path)]
      end

      def handle_missing_file(path)
        message = "Scheduler file not found at #{path}"
        raise SchedulerConfigError, message if @configuration.scheduler_missing_file_policy == :error

        @logger&.warn(message)
        []
      end

      def extract_jobs(payload)
        environment_name = @runtime_context.environment_name
        defaults = fetch_hash(payload, 'defaults')
        env_payload = fetch_hash(payload, environment_name)
        default_jobs = defaults.fetch('jobs', [])
        env_jobs = env_payload.fetch('jobs', [])
        raise SchedulerConfigError, "Expected 'defaults.jobs' to be an array" unless default_jobs.is_a?(Array)
        raise SchedulerConfigError, "Expected '#{environment_name}.jobs' to be an array" unless env_jobs.is_a?(Array)

        default_jobs + env_jobs
      end

      def validate_unique_keys(jobs)
        keys = jobs.map do |job_payload|
          raise SchedulerConfigError, "Each jobs entry must be a mapping, got #{job_payload.class}" unless job_payload.is_a?(Hash)

          @hash_transform.stringify_keys(job_payload)['key'].to_s.strip
        end
        duplicates = keys.group_by(&:itself).select { |key, arr| !key.empty? && arr.size > 1 }.keys
        return if duplicates.empty?

        raise SchedulerConfigError, "Duplicate job keys in scheduler file: #{duplicates.join(', ')}"
      end

      private

      def scheduler_file_path
        configured_path = @configuration.scheduler_config_path.to_s.strip
        raise SchedulerConfigError, 'scheduler_config_path cannot be blank' if configured_path.empty?

        @runtime_context.resolve_path(configured_path)
      end

      def parse_yaml(path)
        rendered = render_yaml_erb(path)
        parsed = YAML.safe_load(rendered) || {}
        raise SchedulerConfigError, "Expected scheduler YAML root to be a mapping in #{path}" unless parsed.is_a?(Hash)

        @hash_transform.stringify_keys(parsed)
      rescue Psych::Exception => e
        raise SchedulerConfigError, "Failed to parse scheduler YAML at #{path}: #{e.message}"
      end

      def render_yaml_erb(path)
        ERB.new(File.read(path), trim_mode: '-').result
      rescue StandardError, SyntaxError => e
        raise SchedulerConfigError, "Failed to evaluate scheduler ERB at #{path}: #{e.message}"
      end

      def fetch_hash(payload, key)
        section = payload.fetch(key)
        raise SchedulerConfigError, "Expected '#{key}' section to be a mapping" unless section.is_a?(Hash)

        section
      rescue KeyError
        {}
      end
    end
  end
end
