# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require_relative 'dispatch_attempt_logger'

module Kaal
  module Backend
    ##
    # Shared module for dispatch logging across backend adapters.
    #
    # Provides methods to log cron job dispatch attempts via the dispatch registry
    # for audit and observability purposes. Adapters that support dispatch logging
    # should include this module and implement a dispatch_registry method.
    #
    # @example Implementing in an adapter
    #   class MyAdapter < Adapter
    #     include DispatchLogging
    #
    #     def dispatch_registry
    #       @dispatch_registry ||= Kaal::Dispatch::MemoryEngine.new
    #     end
    #   end
    module DispatchLogging
      def dispatch_registry
        nil
      end

      ##
      # Log a dispatch attempt via the dispatch registry.
      #
      # Only logs if Kaal.configuration.enable_log_dispatch_registry is true.
      #
      # @param key [String] the lock key (format: "namespace:dispatch:cron_key:fire_time")
      # @return [void]
      def log_dispatch_attempt(key)
        dispatch_attempt_logger.call(key)
      end

      ##
      # Parse a lock key to extract cron job key and fire time.
      #
      # Lock key format: "namespace:dispatch:cron_key:fire_time"
      # Parses by splitting on colon: removes namespace and "dispatch", then
      # rejoins remaining parts as the cron key.
      #
      # @param key [String] the lock key to parse
      # @return [Array<String, Time>] tuple of [cron_key, fire_time]
      def parse_lock_key(key)
        DispatchLogging.parse_lock_key(key)
      end

      def self.parse_lock_key(key)
        parts = key.split(':')
        invalid_message = "Invalid dispatch lock key format: #{key.inspect}"
        dispatch_index = parts[0...-1].rindex('dispatch')
        timestamp = parts[-1]
        valid_key = parts.length >= 4 && dispatch_index&.positive? && timestamp.match?(/\A\d+\z/)
        validate_lock_key!(valid_key, invalid_message)

        fire_time_unix = timestamp.to_i
        cron_key = parts[(dispatch_index + 1)...-1].join(':')
        validate_lock_key!(!cron_key.empty?, invalid_message)

        fire_time = Time.at(fire_time_unix).utc

        [cron_key, fire_time]
      end

      def self.validate_lock_key!(valid, message)
        invalid_dispatch_lock_key!(message) unless valid
      end
      private_class_method :validate_lock_key!

      def self.invalid_dispatch_lock_key!(message)
        raise ArgumentError, message
      end
      private_class_method :invalid_dispatch_lock_key!

      private

      def dispatch_attempt_logger
        @dispatch_attempt_logger ||= DispatchAttemptLogger.new(
          configuration: Kaal.configuration,
          dispatch_registry_provider: -> { dispatch_registry }
        )
      end
    end
  end
end
