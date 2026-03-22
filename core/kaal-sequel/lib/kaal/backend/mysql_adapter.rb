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
    # MySQL named-lock adapter backed by Sequel.
    class MySQLAdapter < Adapter
      include DispatchLogging

      MAX_LOCK_NAME_LENGTH = 64

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

      def acquire(key, _ttl)
        acquired = scalar('SELECT GET_LOCK(?, 0) AS lock_result', self.class.normalize_lock_name(key)) == 1
        log_dispatch_attempt(key) if acquired
        acquired
      rescue StandardError => e
        raise LockAdapterError, "MySQL acquire failed for #{key}: #{e.message}"
      end

      def release(key)
        scalar('SELECT RELEASE_LOCK(?) AS lock_result', self.class.normalize_lock_name(key)) == 1
      rescue StandardError => e
        raise LockAdapterError, "MySQL release failed for #{key}: #{e.message}"
      end

      def self.normalize_lock_name(key)
        return key if key.length <= MAX_LOCK_NAME_LENGTH

        digest = Digest::SHA256.hexdigest(key)
        prefix_length = MAX_LOCK_NAME_LENGTH - 17
        "#{key[0...prefix_length]}:#{digest[0...16]}"
      end

      private

      def scalar(sql, *binds)
        row = @database.connection.fetch(sql, *binds).first
        row.values.first
      end
    end
  end
end
