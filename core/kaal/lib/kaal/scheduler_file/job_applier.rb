# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Kaal
  class SchedulerFileLoader
    # Applies normalized scheduler jobs and rolls them back on failure.
    class JobApplier
      include Kaal::Support::HashTools

      def initialize(configuration:, definition_registry:, registry:, logger:, helper_bundle:)
        @configuration = configuration
        @definition_registry = definition_registry
        @registry = registry
        @logger = logger
        @helper_bundle = helper_bundle
      end

      def apply(job)
        key = job.fetch(:key)
        cron = job.fetch(:cron)
        existing_definition = @definition_registry.find_definition(key)
        existing_registry_entry = @registry.find(key)
        return nil if conflict?(key:, existing_definition:)

        callback = build_callback(job)
        persisted_metadata = persisted_metadata(job)

        @definition_registry.upsert_definition(
          key: key,
          cron: cron,
          enabled: job.fetch(:enabled),
          source: 'file',
          metadata: persisted_metadata
        )

        begin
          @registry.upsert(key: key, cron: cron, enqueue: callback)
        rescue StandardError
          rollback_job(key:, existing_definition:, existing_registry_entry:)
          raise
        end

        { key: key, existing_definition: existing_definition, existing_registry_entry: existing_registry_entry }
      end

      def rollback_jobs(applied_job_contexts)
        applied_job_contexts.reverse_each do |applied_job_context|
          rollback_job(**applied_job_context)
        end
      end

      def conflict?(key:, existing_definition:)
        existing_source = existing_definition&.[](:source)
        return false unless existing_source && existing_source.to_s != 'file'

        policy = @configuration.scheduler_conflict_policy
        case policy
        when :error
          raise SchedulerConfigError, "Scheduler key conflict for '#{key}' with existing source '#{existing_source}'"
        when :code_wins
          @logger&.warn("Skipping scheduler file job '#{key}' because scheduler_conflict_policy is :code_wins")
          true
        when :file_wins
          false
        else
          raise SchedulerConfigError, "Unsupported scheduler_conflict_policy '#{policy}'"
        end
      end

      def rollback_job(key:, existing_definition:, existing_registry_entry:)
        if existing_definition
          definition_attributes = existing_definition.slice(:key, :cron, :enabled, :source, :metadata)
          @definition_registry.upsert_definition(**definition_attributes)
        else
          @definition_registry.remove_definition(key)
        end

        @registry.remove(key) if @registry.registered?(key)

        return unless existing_registry_entry

        @registry.upsert(
          key: existing_registry_entry.key,
          cron: existing_registry_entry.cron,
          enqueue: existing_registry_entry.enqueue
        )
      rescue StandardError => e
        @logger&.error("Failed to rollback scheduler file application for #{key}: #{e.message}")
      end

      private

      def persisted_metadata(job)
        metadata, job_class_name, queue, args, kwargs =
          job.values_at(:metadata, :job_class_name, :queue, :args, :kwargs)
        normalized_metadata = @helper_bundle.stringify_keys(deep_dup(metadata))
        Kaal::Support::HashTools.deep_merge(
          normalized_metadata,
          'execution' => {
            'target' => 'ruby',
            'job_class' => job_class_name,
            'queue' => queue,
            'args' => args,
            'kwargs' => kwargs
          }
        )
      end

      def build_callback(job)
        key = job.fetch(:key)
        job_class_name = job.fetch(:job_class_name)
        queue = job.fetch(:queue)
        args_template = job.fetch(:args)
        kwargs_template = job.fetch(:kwargs)
        job_class = resolve_job_class(job_class_name:, key:)

        lambda do |fire_time:, idempotency_key:|
          context = {
            fire_time: fire_time,
            idempotency_key: idempotency_key,
            key: key
          }
          resolved_args = @helper_bundle.resolve_placeholders(deep_dup(args_template), context)
          raw_kwargs = @helper_bundle.resolve_placeholders(deep_dup(kwargs_template), context) || {}
          raise SchedulerConfigError, "kwargs for scheduler job '#{key}' must be a mapping, got #{raw_kwargs.class}" unless raw_kwargs.is_a?(Hash)

          validate_keyword_keys(raw_kwargs, key)

          resolved_kwargs = raw_kwargs.transform_keys(&:to_sym)
          dispatch_job(job_class, queue, resolved_args, resolved_kwargs)
        end
      end

      def validate_keyword_keys(raw_kwargs, key)
        keys = raw_kwargs.keys
        index = 0
        while index < keys.length
          kwargs_key = keys[index]
          if kwargs_key.is_a?(String) || kwargs_key.is_a?(Symbol)
            index += 1
            next
          end

          raise SchedulerConfigError,
                "Invalid keyword argument key #{kwargs_key.inspect} (#{kwargs_key.class}) for scheduler job '#{key}'"
        end

        nil
      end

      def resolve_job_class(job_class_name:, key:)
        error_message = "Unknown job_class '#{job_class_name}' for key '#{key}'"
        job_class = begin
          Kaal::Support::HashTools.constantize(job_class_name)
        rescue NameError
          nil
        end
        raise_unknown_job_class(error_message) unless job_class

        job_class
      end

      def dispatch_job(job_class, queue, args, kwargs)
        if queue && job_class.respond_to?(:set)
          job_class.set(queue: queue).perform_later(*args, **kwargs)
        elsif job_class.respond_to?(:perform_later)
          job_class.perform_later(*args, **kwargs)
        elsif job_class.respond_to?(:perform)
          job_class.perform(*args, **kwargs)
        else
          raise SchedulerConfigError,
                "job_class '#{job_class.name}' must respond to .perform, .perform_later, or .set(...).perform_later"
        end
      end

      def raise_unknown_job_class(error_message)
        raise SchedulerConfigError, error_message
      end
    end
  end
end
