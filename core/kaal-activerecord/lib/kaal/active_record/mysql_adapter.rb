# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'digest'

module Kaal
  module ActiveRecord
    # MySQL named-lock adapter paired with Active Record registries.
    class MySQLAdapter < Kaal::Backend::Adapter
      include Kaal::Backend::DispatchLogging

      MAX_LOCK_NAME_LENGTH = 64

      def initialize(connection = nil, dispatch_registry: nil, definition_registry: nil)
        super()
        ConnectionSupport.configure!(connection)
        @dispatch_registry = dispatch_registry
        @definition_registry = definition_registry
      end

      def dispatch_registry
        @dispatch_registry ||= DispatchRegistry.new
      end

      def definition_registry
        @definition_registry ||= DefinitionRegistry.new
      end

      def acquire(key, _ttl)
        acquired = scalar('SELECT GET_LOCK(?, 0) AS lock_result', self.class.normalize_lock_name(key)) == 1
        log_dispatch_attempt(key) if acquired
        acquired
      rescue StandardError => e
        raise Kaal::Backend::LockAdapterError, "MySQL acquire failed for #{key}: #{e.message}"
      end

      def release(key)
        scalar('SELECT RELEASE_LOCK(?) AS lock_result', self.class.normalize_lock_name(key)) == 1
      rescue StandardError => e
        raise Kaal::Backend::LockAdapterError, "MySQL release failed for #{key}: #{e.message}"
      end

      def self.normalize_lock_name(key)
        return key if key.length <= MAX_LOCK_NAME_LENGTH

        digest = Digest::SHA256.hexdigest(key)
        prefix_length = MAX_LOCK_NAME_LENGTH - 17
        "#{key[0...prefix_length]}:#{digest[0...16]}"
      end

      private

      def scalar(sql, value)
        result = BaseRecord.connection.exec_query(
          BaseRecord.send(:sanitize_sql_array, [sql, value])
        )
        result.first.values.first
      end
    end
  end
end
