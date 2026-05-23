# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
module Kaal
  module Backend
    # MySQL-backed backend for either Sequel or Active Record persistence.
    class MySQL < Adapter
      UNSET_SKIP_LOCKED_SUPPORT = Object.new.freeze

      def initialize(database: nil, connection: nil, namespace: nil,
                     use_skip_locked: UNSET_SKIP_LOCKED_SUPPORT)
        super()
        backend_class = self.class
        @engine = if database
                    Kaal::Sequel.require_sequel!
                    require 'kaal/internal/sequel'
                    backend_class.send(:build_sequel_backend, database, namespace, use_skip_locked)
                  else
                    Kaal::ActiveRecord.require_activerecord!
                    require 'kaal/internal/active_record'
                    backend_class.send(:build_active_record_backend, connection, namespace, use_skip_locked)
                  end
      end

      def dispatch_registry
        @engine.dispatch_registry
      end

      def definition_registry
        @engine.definition_registry
      end

      def delayed_store
        @engine.delayed_store
      end

      def acquire(key, ttl)
        @engine.acquire(key, ttl)
      end

      def release(key)
        @engine.release(key)
      end

      def self.build_sequel_backend(database, namespace, use_skip_locked)
        return Kaal::Internal::Sequel::MySQLBackend.new(database, namespace:) if use_skip_locked.equal?(UNSET_SKIP_LOCKED_SUPPORT)

        Kaal::Internal::Sequel::MySQLBackend.new(database, namespace:, use_skip_locked:)
      end
      private_class_method :build_sequel_backend

      def self.build_active_record_backend(connection, namespace, use_skip_locked)
        return Kaal::Internal::ActiveRecord::MySQLBackend.new(connection, namespace:) if use_skip_locked.equal?(UNSET_SKIP_LOCKED_SUPPORT)

        Kaal::Internal::ActiveRecord::MySQLBackend.new(connection, namespace:, use_skip_locked:)
      end
      private_class_method :build_active_record_backend
    end
  end
end
