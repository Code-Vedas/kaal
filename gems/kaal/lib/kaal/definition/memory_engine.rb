# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require_relative 'registry'
require_relative 'persistence_helpers'
require 'kaal/support/hash_tools'

module Kaal
  module Definition
    # In-memory definition registry used when no persistent backend is configured.
    class MemoryEngine < Registry
      include Kaal::Support::HashTools

      def initialize
        super
        @definitions = {}
        @mutex = Mutex.new
      end

      def upsert_definition(key:, cron:, enabled: true, source: 'code', metadata: {})
        @mutex.synchronize do
          now = Time.now.utc
          existing = @definitions[key]
          definition = {
            key: key,
            cron: cron,
            enabled: enabled,
            source: source,
            metadata: deep_dup(metadata || {}),
            created_at: existing ? existing[:created_at] : now,
            updated_at: now,
            disabled_at: PersistenceHelpers.disabled_at_for(existing, enabled, now)
          }
          @definitions[key] = definition
          deep_dup(definition)
        end
      end

      def remove_definition(key)
        @mutex.synchronize { deep_dup(@definitions.delete(key)) }
      end

      def find_definition(key)
        @mutex.synchronize { deep_dup(@definitions[key]) }
      end

      def all_definitions
        @mutex.synchronize { @definitions.values.sort_by { |definition| definition[:key] }.map { |definition| deep_dup(definition) } }
      end

      def clear
        @mutex.synchronize { @definitions.clear }
      end
    end
  end
end
