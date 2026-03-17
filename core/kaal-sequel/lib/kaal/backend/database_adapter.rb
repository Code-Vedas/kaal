# frozen_string_literal: true

require 'sequel'
require 'kaal/backend/dispatch_logging'
require_relative '../definition/database_engine'
require_relative '../dispatch/database_engine'
require 'kaal/persistence/database'

module Kaal
  module Backend
    # Sequel-backed SQL adapter that coordinates locks through the kaal_locks table.
    class DatabaseAdapter < Adapter
      include DispatchLogging

      def initialize(database)
        super()
        @database = Kaal::Persistence::Database.new(database)
      end

      def dispatch_registry
        @dispatch_registry ||= Kaal::Dispatch::DatabaseEngine.new(database: @database.connection)
      end

      def definition_registry
        @definition_registry ||= Kaal::Definition::DatabaseEngine.new(database: @database.connection)
      end

      def acquire(key, ttl)
        now = Time.now.utc
        expires_at = now + ttl

        2.times do |attempt|
          cleanup_expired_locks if attempt.positive?

          begin
            dataset.insert(key: key, acquired_at: now, expires_at: expires_at)
            log_dispatch_attempt(key)
            return true
          rescue ::Sequel::UniqueConstraintViolation
            next
          end
        end

        false
      rescue StandardError => e
        raise LockAdapterError, "Database acquire failed for #{key}: #{e.message}"
      end

      def release(key)
        dataset.where(key: key).delete.positive?
      rescue StandardError => e
        raise LockAdapterError, "Database release failed for #{key}: #{e.message}"
      end

      def cleanup_expired_locks
        dataset.where { expires_at < Time.now.utc }.delete
      end

      private

      def dataset
        @database.locks_dataset
      end
    end

    SQLiteAdapter = DatabaseAdapter
  end
end
