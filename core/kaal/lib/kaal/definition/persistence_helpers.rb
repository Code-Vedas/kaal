# frozen_string_literal: true

require 'json'

module Kaal
  module Definition
    # Shared pure helpers for persisted definition rows and metadata.
    module PersistenceHelpers
      module_function

      def disabled_at_for(existing, enabled, now)
        return nil if enabled
        return existing[:disabled_at] if existing && existing[:enabled] == false

        now
      end

      def parse_metadata(value)
        return {} if value.to_s.empty?

        JSON.parse(value, symbolize_names: true)
      rescue JSON::ParserError
        {}
      end
    end
  end
end
