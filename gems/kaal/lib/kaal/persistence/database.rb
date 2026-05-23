# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
module Kaal
  module Persistence
    # Thin wrapper around a Sequel connection to keep table access consistent.
    class Database
      attr_reader :connection

      def initialize(connection)
        Kaal::Sequel.require_sequel!
        @connection = if connection.is_a?(::Sequel::Database)
                        connection
                      else
                        ::Sequel.connect(connection)
                      end
      end

      def definitions_dataset
        connection[:kaal_definitions]
      end

      def dispatches_dataset
        connection[:kaal_dispatches]
      end

      def locks_dataset
        connection[:kaal_locks]
      end

      def delayed_jobs_dataset
        connection[:kaal_delayed_jobs]
      end
    end
  end
end
