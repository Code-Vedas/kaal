# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Kaal
  class SchedulerFileLoader
    # Normalizes scheduler job payloads into application-ready hashes.
    class JobNormalizer
      def initialize(hash_transform:, placeholder_support:, cron_validator:)
        @hash_transform = hash_transform
        @placeholder_support = placeholder_support
        @cron_validator = cron_validator
      end

      def call(job_payload)
        payload = @hash_transform.stringify_keys(job_payload)
        key = payload.fetch('key', '').to_s.strip
        raise SchedulerConfigError, 'Job key cannot be blank' if key.empty?

        cron = required_string(payload, field: 'cron', error_prefix: "Job cron cannot be blank for key '#{key}'")
        job_class_name = required_string(payload, field: 'job_class', error_prefix: "Job class cannot be blank for key '#{key}'")
        validate_cron(key:, cron:)
        options = extract_job_options(payload, key:)

        {
          key: key,
          cron: cron,
          job_class_name: job_class_name,
          **options
        }
      end

      private

      def required_string(payload, field:, error_prefix:)
        value = payload.fetch(field, '').to_s.strip
        raise SchedulerConfigError, error_prefix if value.empty?

        value
      end

      def validate_cron(key:, cron:)
        return if @cron_validator.call(cron)

        raise SchedulerConfigError, "Invalid cron expression '#{cron}' for key '#{key}'"
      end

      def extract_job_options(payload, key:)
        metadata, args, kwargs, queue, enabled_value = payload.values_at('metadata', 'args', 'kwargs', 'queue', 'enabled')
        args ||= []
        kwargs ||= {}
        enabled = true
        if payload.key?('enabled')
          raise SchedulerConfigError, "enabled must be a boolean for key '#{key}'" unless enabled_value.is_a?(TrueClass) || enabled_value.is_a?(FalseClass)

          enabled = enabled_value
        end

        raise SchedulerConfigError, "metadata must be a mapping for key '#{key}'" if metadata && !metadata.is_a?(Hash)

        validate_job_option_types(key:, args:, kwargs:, queue:)
        @placeholder_support.validate_placeholders(args, key:)
        @placeholder_support.validate_placeholders(kwargs, key:)

        {
          queue: queue,
          args: args.deep_dup,
          kwargs: kwargs.deep_dup,
          enabled: enabled,
          metadata: metadata ? metadata.deep_dup : {}
        }
      end

      def validate_job_option_types(key:, args:, kwargs:, queue:)
        raise SchedulerConfigError, "args must be an array for key '#{key}'" unless args.is_a?(Array)
        raise SchedulerConfigError, "kwargs must be a mapping for key '#{key}'" unless kwargs.is_a?(Hash)
        raise SchedulerConfigError, "queue must be a string for key '#{key}'" if queue && !queue.is_a?(String)
        return if kwargs.keys.all? { |kwargs_key| kwargs_key.is_a?(String) || kwargs_key.is_a?(Symbol) }

        raise SchedulerConfigError, "kwargs keys must be strings or symbols for key '#{key}'"
      end
    end
  end
end
