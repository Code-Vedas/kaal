# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
module Kaal
  # Shared job-class resolution and dispatch rules used by recurring and delayed jobs.
  module JobDispatcher
    module_function

    def resolve_job_class(job_class_name:, key:, queue: nil, apply_delayed_job_allow_list: true)
      job_class = normalize_job_class(job_class_name, key, apply_delayed_job_allow_list:)
      validate_dispatch_interface(job_class, key, queue)
    end

    def normalized_job_class_name(job_class_name:, key:, apply_delayed_job_allow_list: true)
      normalized_job_class_name = normalize_job_class_name(job_class_name)
      raise SchedulerConfigError, "Job class cannot be blank for key '#{key}'" if normalized_job_class_name.empty?

      return normalized_job_class_name unless apply_delayed_job_allow_list

      validate_allowed_job_class_name!(job_class_name: normalized_job_class_name, key:)
      normalized_job_class_name
    end

    def dispatch(job_class:, queue:, args:)
      job_class_name = job_class.name

      if queue && !job_class.respond_to?(:set)
        raise SchedulerConfigError,
              "job_class '#{job_class_name}' must respond to .set to use queue #{queue.inspect}"
      end

      if queue
        job_class.set(queue: queue).perform_later(*args)
      elsif job_class.respond_to?(:perform_later)
        job_class.perform_later(*args)
      elsif job_class.respond_to?(:perform)
        job_class.perform(*args)
      else
        raise SchedulerConfigError,
              "job_class '#{job_class_name}' must respond to .perform, .perform_later, or .set(...).perform_later"
      end
    end

    def active_job_dispatch?(job_class, queue)
      (queue && job_class.respond_to?(:set)) || job_class.respond_to?(:perform_later)
    end

    def normalize_job_class_name(job_class)
      case job_class
      when Module
        job_class.name.to_s.strip
      else
        job_class.to_s.strip
      end
    end

    def normalize_job_class(job_class_name, key, apply_delayed_job_allow_list: true)
      normalized_job_class_name = normalized_job_class_name(
        job_class_name:,
        key:,
        apply_delayed_job_allow_list:
      )

      return job_class_name if job_class_name.is_a?(Module)

      job_class = begin
        Kaal::Support::HashTools.constantize(normalized_job_class_name)
      rescue NameError
        nil
      end

      return job_class if job_class

      raise SchedulerConfigError, "Unknown job_class #{normalized_job_class_name.inspect} for key '#{key}'"
    end
    private_class_method :normalize_job_class

    def validate_allowed_job_class_name!(job_class_name:, key:)
      allowed_prefixes = Array(Kaal.configuration.delayed_job_allowed_class_prefixes)
      return if allowed_prefixes.empty?
      return if allowed_prefixes.any? { |prefix| job_class_name.start_with?(prefix) }

      raise SchedulerConfigError,
            "job_class '#{job_class_name}' for key '#{key}' is not allowed by delayed_job_allowed_class_prefixes"
    end
    private_class_method :validate_allowed_job_class_name!

    def validate_dispatch_interface(job_class, key, queue)
      queue_present = !queue.nil?
      no_queue = !queue_present
      supports_set = job_class.respond_to?(:set)
      supports_perform_later = job_class.respond_to?(:perform_later)
      supports_perform = job_class.respond_to?(:perform)

      return job_class if queue_present && supports_set
      return job_class if no_queue && supports_perform_later
      return job_class if no_queue && supports_perform

      raise SchedulerConfigError,
            "job_class '#{job_class.name}' for key '#{key}' must respond to .perform, .perform_later, or .set(...).perform_later"
    end
    private_class_method :validate_dispatch_interface
  end
end
