# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'digest'

module Kaal
  module ActiveRecord
    # PostgreSQL advisory-lock adapter paired with Active Record registries.
    class PostgresAdapter < Kaal::Backend::Adapter
      include Kaal::Backend::DispatchLogging

      SIGNED_64_MAX = 9_223_372_036_854_775_807
      UNSIGNED_64_RANGE = 18_446_744_073_709_551_616

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
        acquired = scalar('SELECT pg_try_advisory_lock(?) AS acquired', self.class.calculate_lock_id(key)) == true
        log_dispatch_attempt(key) if acquired
        acquired
      rescue StandardError => e
        raise Kaal::Backend::LockAdapterError, "PostgreSQL acquire failed for #{key}: #{e.message}"
      end

      def release(key)
        scalar('SELECT pg_advisory_unlock(?) AS released', self.class.calculate_lock_id(key)) == true
      rescue StandardError => e
        raise Kaal::Backend::LockAdapterError, "PostgreSQL release failed for #{key}: #{e.message}"
      end

      def self.calculate_lock_id(key)
        hash = Digest::MD5.digest(key).unpack1('Q>')
        hash > SIGNED_64_MAX ? hash - UNSIGNED_64_RANGE : hash
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
