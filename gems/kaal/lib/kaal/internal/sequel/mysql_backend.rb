# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'digest'
require 'kaal/backend/dispatch_logging'
require 'kaal/persistence/database'

module Kaal
  module Internal
    module Sequel
      # MySQL named-lock engine backed by Sequel.
      class MySQLBackend < Kaal::Backend::Adapter
        include Kaal::Backend::DispatchLogging

        MAX_LOCK_NAME_LENGTH = 64
        UNSET_SKIP_LOCKED_SUPPORT = Object.new.freeze

        def initialize(database, namespace: nil, use_skip_locked: UNSET_SKIP_LOCKED_SUPPORT)
          super()
          @database = Kaal::Persistence::Database.new(database)
          @namespace = namespace
          @use_skip_locked = use_skip_locked
        end

        def dispatch_registry
          @dispatch_registry ||= Kaal::Dispatch::DatabaseEngine.new(database: @database.connection, namespace: resolved_namespace)
        end

        def definition_registry
          @definition_registry ||= Kaal::Definition::DatabaseEngine.new(database: @database.connection)
        end

        def delayed_store
          @delayed_store ||= Kaal::DelayedJob::DatabaseEngine.new(database: @database.connection, use_skip_locked: supports_skip_locked?)
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

        def scalar(sql, *binds)
          row = @database.connection.fetch(sql, *binds).first
          row.values.first
        end

        def resolved_namespace
          @namespace || Kaal.configuration.namespace
        end

        def supports_skip_locked?
          return @use_skip_locked unless @use_skip_locked.equal?(UNSET_SKIP_LOCKED_SUPPORT)

          version_string = scalar('SELECT VERSION() AS version')
          Kaal::DelayedJob::MySQLVersionSupport.skip_locked_supported?(version_string)
        end
      end
    end
  end
end
