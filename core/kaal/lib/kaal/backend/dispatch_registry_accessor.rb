# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
module Kaal
  module Backend
    # Reads dispatch registry state through the configured backend adapter.
    class DispatchRegistryAccessor
      def initialize(configuration:)
        @configuration = configuration
      end

      def dispatched?(key, fire_time)
        registry = fetch_registry
        return false unless registry

        registry.dispatched?(key, fire_time)
      rescue StandardError => e
        @configuration.logger&.warn("Error checking dispatch status for #{key}: #{e.message}")
        false
      end

      def registry
        fetch_registry
      rescue StandardError => e
        @configuration.logger&.warn("Error accessing dispatch registry: #{e.message}")
        nil
      end

      private

      def fetch_registry
        adapter = @configuration.backend
        return nil unless adapter
        return nil unless adapter.respond_to?(:dispatch_registry)

        adapter.dispatch_registry
      end
    end
  end
end
