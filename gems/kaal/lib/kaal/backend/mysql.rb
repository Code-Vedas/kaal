# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
module Kaal
  module Backend
    # MySQL-backed backend for either Sequel or Active Record persistence.
    class MySQL < Adapter
      def initialize(database: nil, connection: nil, namespace: nil, **)
        super()
        @engine = if database
                    Kaal::Sequel.require_sequel!
                    require 'kaal/internal/sequel'
                    Kaal::Internal::Sequel::MySQLBackend.new(database, namespace:)
                  else
                    Kaal::ActiveRecord.require_activerecord!
                    require 'kaal/internal/active_record'
                    Kaal::Internal::ActiveRecord::MySQLBackend.new(connection, namespace:, **)
                  end
      end

      def dispatch_registry
        @engine.dispatch_registry
      end

      def definition_registry
        @engine.definition_registry
      end

      def acquire(key, ttl)
        @engine.acquire(key, ttl)
      end

      def release(key)
        @engine.release(key)
      end
    end
  end
end
