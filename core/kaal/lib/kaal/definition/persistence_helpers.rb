# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
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
