# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'active_support/core_ext/hash/deep_merge'
require 'active_support/core_ext/object/deep_dup'
require 'active_support/core_ext/string/inflections'
require 'kaal/runtime/runtime_context'
require 'kaal/scheduler_file/hash_transform'
require 'kaal/scheduler_file/placeholder_support'
require_relative 'helper_bundle'
require_relative 'payload_loader'
require_relative 'job_normalizer'
require_relative 'job_applier'

module Kaal
  # Loads scheduler definitions from config/scheduler.yml and registers them.
  class SchedulerFileLoader
    include SchedulerHashTransform
    include SchedulerPlaceholderSupport

    PLACEHOLDER_PATTERN = /\{\{\s*([a-zA-Z0-9_.]+)\s*\}\}/
    ALLOWED_PLACEHOLDERS = {
      'fire_time.iso8601' => ->(ctx) { ctx.fetch(:fire_time).iso8601 },
      'fire_time.unix' => ->(ctx) { ctx.fetch(:fire_time).to_i },
      'idempotency_key' => ->(ctx) { ctx.fetch(:idempotency_key) },
      'key' => ->(ctx) { ctx.fetch(:key) }
    }.freeze

    def initialize(
      configuration:,
      definition_registry:,
      registry:,
      logger:,
      runtime_context: RuntimeContext.default
    )
      @configuration = configuration
      @definition_registry = definition_registry
      @registry = registry
      @logger = logger
      @runtime_context = runtime_context
      @placeholder_resolvers = ALLOWED_PLACEHOLDERS
    end

    def load
      applied_job_contexts = []
      path, payload = payload_loader.load
      return handle_missing_file(path) unless payload

      jobs = extract_jobs(payload)
      validate_unique_keys(jobs)
      normalized_jobs = jobs.map { |job_payload| normalize_job(job_payload) }
      applied_jobs = []
      normalized_jobs.each do |job|
        applied_job_context = apply_job(job)
        next unless applied_job_context

        applied_jobs << job
        applied_job_contexts << applied_job_context
      end

      applied_jobs
    rescue StandardError
      rollback_applied_jobs(applied_job_contexts)
      raise
    end

    private

    def handle_missing_file(path)
      payload_loader.handle_missing_file(path)
    end

    def extract_jobs(payload)
      payload_loader.extract_jobs(payload)
    end

    def validate_unique_keys(jobs)
      payload_loader.validate_unique_keys(jobs)
    end

    def normalize_job(job_payload)
      job_normalizer.call(job_payload)
    end

    def extract_job_options(payload, key:)
      job_normalizer.send(:extract_job_options, payload, key:)
    end

    def apply_job(job)
      job_applier.apply(job)
    end

    def rollback_applied_jobs(applied_job_contexts = [])
      job_applier.rollback_jobs(applied_job_contexts)
    end

    def rollback_applied_job(key:, existing_definition:, existing_registry_entry:)
      job_applier.rollback_job(key:, existing_definition:, existing_registry_entry:)
    end

    def skip_due_to_conflict?(key:, existing_definition:)
      job_applier.conflict?(key:, existing_definition:)
    end

    def build_callback(key:, job_class_name:, queue:, args_template:, kwargs_template:)
      job_applier.send(
        :build_callback,
        {
          key: key,
          job_class_name: job_class_name,
          queue: queue,
          args: args_template,
          kwargs: kwargs_template
        }
      )
    end

    def resolve_job_class(job_class_name:, key:)
      job_applier.send(:resolve_job_class, job_class_name:, key:)
    end

    def payload_loader
      @payload_loader ||= PayloadLoader.new(
        configuration: @configuration,
        runtime_context: @runtime_context,
        logger: @logger,
        hash_transform: helper_bundle
      )
    end

    def job_normalizer
      @job_normalizer ||= JobNormalizer.new(
        hash_transform: helper_bundle,
        placeholder_support: helper_bundle,
        cron_validator: ->(cron) { Kaal.valid?(cron) }
      )
    end

    def job_applier
      @job_applier ||= JobApplier.new(
        configuration: @configuration,
        definition_registry: @definition_registry,
        registry: @registry,
        logger: @logger,
        helper_bundle: helper_bundle
      )
    end

    def helper_bundle
      @helper_bundle ||= HelperBundle.new(loader: self)
    end
  end
end
