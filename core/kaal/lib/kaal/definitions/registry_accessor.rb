# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Kaal
  module Definitions
    # Resolves the active definition registry with an in-memory fallback.
    class RegistryAccessor
      def initialize(configuration:, fallback_registry_provider:)
        @configuration = configuration
        @fallback_registry_provider = fallback_registry_provider
      end

      def call
        configured_backend = @configuration.backend
        registry = configured_backend&.definition_registry
        return registry if registry

        fallback_registry
      rescue NoMethodError
        fallback_registry
      end

      private

      def fallback_registry
        @fallback_registry_provider.call
      end
    end
  end
end
