# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'socket'

module Kaal
  module Backend
    # Logs dispatch attempts through a backend-provided dispatch registry.
    class DispatchAttemptLogger
      def initialize(configuration:, dispatch_registry_provider:, logger: nil, node_id_provider: Socket.method(:gethostname))
        @configuration = configuration
        @dispatch_registry_provider = dispatch_registry_provider
        @logger = logger
        @node_id_provider = node_id_provider
      end

      def call(lock_key)
        return unless @configuration.enable_log_dispatch_registry

        registry = @dispatch_registry_provider.call
        return unless registry

        cron_key, fire_time = DispatchLogging.parse_lock_key(lock_key)
        registry.log_dispatch(cron_key, fire_time, @node_id_provider.call, 'dispatched')
      rescue StandardError => e
        (@logger || @configuration.logger)&.error("Failed to log dispatch for #{lock_key}: #{e.message}")
      end
    end
  end
end
