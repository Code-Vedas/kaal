# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'kaal/version'
require 'kaal/config'
require 'kaal/registry'
require 'kaal/dispatch/registry'
require 'kaal/dispatch/memory_engine'
require 'kaal/dispatch/redis_engine'
require 'kaal/definition/registry'
require 'kaal/definition/memory_engine'
require 'kaal/definition/redis_engine'
require 'kaal/backend/adapter'
require 'kaal/backend/memory_adapter'
require 'kaal/backend/redis_adapter'
require 'kaal/backend/dispatch_registry_accessor'
require 'kaal/backend/dispatch_attempt_logger'
require 'kaal/utils'
require 'kaal/register_conflict_support'
require 'kaal/definitions/registry_accessor'
require 'kaal/definitions/registration_service'
require 'kaal/runtime'
require 'kaal/scheduler_file'
require 'kaal/core'
require 'kaal/support/hash_tools'

# Plain-Ruby scheduler surface with configurable backends, registries, and CLI helpers.
module Kaal
  class << self
    include RegisterConflictSupport

    def configuration
      @configuration ||= Configuration.new
    end

    def registry
      @registry ||= Registry.new
    end

    def coordinator
      @coordinator ||= Coordinator.new(configuration: configuration, registry: registry)
    end

    def reset_configuration!
      @configuration = Configuration.new
      @coordinator = nil
      @definition_registry = nil
      @definitions_registry_accessor = nil
      @dispatch_registry_accessor = nil
    end

    def reset_registry!
      @registry = Registry.new
      definition_registry = @definition_registry
      definition_registry.clear if definition_registry.respond_to?(:clear)
      @coordinator = nil
    end

    def reset_coordinator!
      if @coordinator&.running?
        stopped = @coordinator.stop!
        raise 'Failed to stop coordinator thread within timeout' unless stopped
      end

      @coordinator = nil
      coordinator
    end

    def configure
      yield(configuration) if block_given?
    end

    def register(key:, cron:, enqueue:)
      registration_service.call(key:, cron:, enqueue:)
    end

    def load_scheduler_file!(runtime_context: RuntimeContext.default)
      SchedulerFileLoader.new(
        configuration: configuration,
        definition_registry: definition_registry,
        registry: registry,
        logger: configuration.logger,
        runtime_context: runtime_context
      ).load
    end

    def unregister(key:)
      definition_registry.remove_definition(key)
      registry.remove(key)
    end

    def registered
      definition_registry.all_definitions.map do |definition|
        key = definition[:key]
        callback = registry.find(key)&.enqueue
        Registry::Entry.new(key: key, cron: definition[:cron], enqueue: callback).freeze
      end
    end

    def registered?(key:)
      !!definition_registry.find_definition(key)
    end

    def enable(key:)
      definition_registry.enable_definition(key)
    end

    def disable(key:)
      definition_registry.disable_definition(key)
    end

    def start!
      coordinator.start!
    end

    def stop!(timeout: 30)
      coordinator.stop!(timeout: timeout)
    end

    def running?
      coordinator.running?
    end

    def restart!
      coordinator.restart!
    end

    def tick!
      coordinator.tick!
    end

    def with_idempotency(key, fire_time)
      raise ArgumentError, 'block required' unless block_given?

      yield(IdempotencyKeyGenerator.call(key, fire_time, configuration: configuration))
    end

    def dispatched?(key, fire_time)
      dispatch_registry_accessor.dispatched?(key, fire_time)
    end

    def dispatch_log_registry
      dispatch_registry_accessor.registry
    end

    def tick_interval = configuration.tick_interval
    def window_lookback = configuration.window_lookback
    def window_lookahead = configuration.window_lookahead
    def lease_ttl = configuration.lease_ttl
    def namespace = configuration.namespace
    def backend = configuration.backend
    def logger = configuration.logger
    def time_zone = configuration.time_zone

    def tick_interval=(value)
      configuration.tick_interval = value
    end

    def window_lookback=(value)
      configuration.window_lookback = value
    end

    def window_lookahead=(value)
      configuration.window_lookahead = value
    end

    def lease_ttl=(value)
      configuration.lease_ttl = value
    end

    def namespace=(value)
      configuration.namespace = value
    end

    def backend=(value)
      configuration.backend = value
    end

    def logger=(value)
      configuration.logger = value
    end

    def time_zone=(value)
      configuration.time_zone = value
    end

    def definition_registry
      definitions_registry_accessor.call
    end

    def validate
      configuration.validate
    end

    def validate!
      configuration.validate!
    end

    def valid?(expression)
      CronUtils.valid?(expression)
    end

    def simplify(expression)
      CronUtils.simplify(expression)
    end

    def lint(expression)
      CronUtils.lint(expression)
    end

    def to_human(expression, locale: nil)
      CronHumanizer.to_human(expression, locale: locale)
    end

    private

    def rollback_registered_definition(key, existing_definition)
      if existing_definition
        definition_registry.upsert_definition(
          **Definition::AttributeHelpers.definition_attributes(existing_definition), enabled: existing_definition[:enabled]
        )
      elsif !registry.registered?(key)
        definition_registry.remove_definition(key)
      end
    end

    def registration_service
      @registration_service ||= Definitions::RegistrationService.new(
        configuration: configuration,
        definition_registry: definition_registry,
        registry: registry
      )
    end

    def definitions_registry_accessor
      @definitions_registry_accessor ||= Definitions::RegistryAccessor.new(
        configuration: configuration,
        fallback_registry_provider: lambda {
          @definition_registry ||= Definition::MemoryEngine.new
        }
      )
    end

    def dispatch_registry_accessor
      @dispatch_registry_accessor ||= Backend::DispatchRegistryAccessor.new(configuration: configuration)
    end
  end
end
