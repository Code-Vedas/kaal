# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Kaal
  class SchedulerFileLoader
    # Exposes hash/placeholder helpers to extracted scheduler-file collaborators.
    class HelperBundle
      def initialize(loader:)
        @loader = loader
      end

      def stringify_keys(payload)
        @loader.send(:stringify_keys, payload)
      end

      def resolve_placeholders(value, context)
        @loader.send(:resolve_placeholders, value, context)
      end

      def validate_placeholders(value, key:)
        @loader.send(:validate_placeholders, value, key:)
      end
    end
  end
end
