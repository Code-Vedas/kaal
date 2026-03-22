# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'kaal/backend/adapter'
require 'kaal/backend/dispatch_logging'

module Kaal
  module ActiveRecord
    # Table-backed lock adapter used for SQLite-style Active Record storage.
    class DatabaseAdapter < Kaal::Backend::Adapter
      include Kaal::Backend::DispatchLogging

      def initialize(connection = nil, lock_model: LockRecord, dispatch_registry: nil, definition_registry: nil)
        super()
        ConnectionSupport.configure!(connection)
        @lock_model = lock_model
        @dispatch_registry = dispatch_registry
        @definition_registry = definition_registry
      end

      def dispatch_registry
        @dispatch_registry ||= DispatchRegistry.new
      end

      def definition_registry
        @definition_registry ||= DefinitionRegistry.new
      end

      def acquire(key, ttl)
        now = Time.now.utc
        expires_at = now + ttl

        2.times do |attempt|
          cleanup_expired_locks if attempt.positive?

          begin
            @lock_model.create!(key: key, acquired_at: now, expires_at: expires_at)
            log_dispatch_attempt(key)
            return true
          rescue ::ActiveRecord::RecordNotUnique
            next
          end
        end

        false
      rescue StandardError => e
        raise Kaal::Backend::LockAdapterError, "Database acquire failed for #{key}: #{e.message}"
      end

      def release(key)
        @lock_model.where(key: key).delete_all.positive?
      rescue StandardError => e
        raise Kaal::Backend::LockAdapterError, "Database release failed for #{key}: #{e.message}"
      end

      def cleanup_expired_locks
        @lock_model.where(expires_at: ...Time.now.utc).delete_all
      end
    end

    SQLiteAdapter = DatabaseAdapter
  end
end
