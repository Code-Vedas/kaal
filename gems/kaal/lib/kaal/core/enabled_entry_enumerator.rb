# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
module Kaal
  # Enumerates scheduler entries from persisted definitions or the in-memory registry.
  class EnabledEntryEnumerator
    def initialize(configuration:, registry:, definition_registry_provider: -> { Kaal.definition_registry })
      @configuration = configuration
      @registry = registry
      @definition_registry_provider = definition_registry_provider
    end

    def each(&)
      resolve_entries.each(&)
    rescue StandardError => e
      @configuration.logger&.warn("Failed to iterate enabled definitions: #{e.message}")
      yield_registry_entries(&)
    end

    private

    def yield_registry_entries(&)
      @registry.each(&)
    end

    def resolve_entries
      registry_entries = @registry.to_enum
      definition_registry = @definition_registry_provider.call
      return registry_entries unless definition_registry

      definitions = definition_registry.enabled_definitions || []
      return registry_entries if definitions.empty? && definition_registry.all_definitions.to_a.empty?

      definitions.filter_map { |definition| build_entry(definition) }
    end

    def build_entry(definition)
      key = definition[:key]
      callback_entry = @registry.find(key)
      unless callback_entry&.enqueue
        @configuration.logger&.warn("No enqueue callback registered for definition '#{key}', skipping")
        return nil
      end

      Registry::Entry.new(key: key, cron: definition[:cron], enqueue: callback_entry.enqueue).freeze
    end
  end
end
