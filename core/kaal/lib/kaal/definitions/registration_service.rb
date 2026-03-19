# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
module Kaal
  module Definitions
    # Registers code-defined jobs while preserving persisted definition state.
    class RegistrationService
      include RegisterConflictSupport

      attr_reader :configuration, :definition_registry, :registry

      def initialize(configuration:, definition_registry:, registry:)
        @configuration = configuration
        @definition_registry = definition_registry
        @registry = registry
      end

      def call(key:, cron:, enqueue:)
        existing_definition = @definition_registry.find_definition(key)
        existing_entry = @registry.find(key)
        if existing_entry
          conflict_result = resolve_register_conflict(
            key: key,
            cron: cron,
            enqueue: enqueue,
            existing_definition: existing_definition,
            existing_entry: existing_entry
          )

          return conflict_result if conflict_result

          raise RegistryError, "Key '#{key}' is already registered"
        end

        persisted_attributes = {
          enabled: true,
          source: 'code',
          metadata: {}
        }.merge(existing_definition&.slice(:enabled, :metadata) || {})
        @definition_registry.upsert_definition(key: key, cron: cron, **persisted_attributes)
        with_registered_definition_rollback(key, existing_definition) do
          @registry.add(key: key, cron: cron, enqueue: enqueue)
        end
      end

      private

      def rollback_registered_definition(key, existing_definition)
        if existing_definition
          @definition_registry.upsert_definition(**existing_definition.slice(:key, :cron, :enabled, :source, :metadata))
        elsif !@registry.registered?(key)
          @definition_registry.remove_definition(key)
        end
      end
    end
  end
end
