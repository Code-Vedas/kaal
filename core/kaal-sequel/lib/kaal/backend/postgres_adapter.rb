# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'digest'
require 'kaal/backend/dispatch_logging'
require_relative '../definition/database_engine'
require_relative '../dispatch/database_engine'
require 'kaal/persistence/database'

module Kaal
  module Backend
    # PostgreSQL advisory-lock adapter backed by Sequel.
    class PostgresAdapter < Adapter
      include DispatchLogging

      SIGNED_64_MAX = 9_223_372_036_854_775_807
      UNSIGNED_64_RANGE = 18_446_744_073_709_551_616

      def initialize(database, namespace: nil)
        super()
        @database = Kaal::Persistence::Database.new(database)
        @namespace = namespace
      end

      def dispatch_registry
        @dispatch_registry ||= Kaal::Dispatch::DatabaseEngine.new(database: @database.connection, namespace: resolved_namespace)
      end

      def definition_registry
        @definition_registry ||= Kaal::Definition::DatabaseEngine.new(database: @database.connection)
      end

      def acquire(key, _ttl)
        acquired = scalar('SELECT pg_try_advisory_lock(?) AS acquired', self.class.calculate_lock_id(key)) == true
        log_dispatch_attempt(key) if acquired
        acquired
      rescue StandardError => e
        raise LockAdapterError, "PostgreSQL acquire failed for #{key}: #{e.message}"
      end

      def release(key)
        scalar('SELECT pg_advisory_unlock(?) AS released', self.class.calculate_lock_id(key)) == true
      rescue StandardError => e
        raise LockAdapterError, "PostgreSQL release failed for #{key}: #{e.message}"
      end

      def self.calculate_lock_id(key)
        hash = Digest::MD5.digest(key).unpack1('Q>')
        hash > SIGNED_64_MAX ? hash - UNSIGNED_64_RANGE : hash
      end

      private

      def scalar(sql, *binds)
        row = @database.connection.fetch(sql, *binds).first
        row.values.first
      end

      def resolved_namespace
        @namespace || Kaal.configuration.namespace
      end
    end
  end
end
