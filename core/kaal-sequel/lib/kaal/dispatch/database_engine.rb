# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'kaal/dispatch/registry'
require 'kaal/persistence/database'

module Kaal
  module Dispatch
    # Sequel-backed dispatch registry stored in kaal_dispatches.
    class DatabaseEngine < Registry
      def initialize(database:)
        super()
        @database = Kaal::Persistence::Database.new(database)
      end

      def log_dispatch(key, fire_time, node_id, status = 'dispatched')
        now = Time.now.utc
        attributes = {
          key: key,
          fire_time: fire_time,
          dispatched_at: now,
          node_id: node_id,
          status: status
        }
        dispatches_dataset = dataset
        update_values = { dispatched_at: now, node_id: node_id, status: status }
        begin
          dispatches_dataset.insert_conflict(
            target: %i[key fire_time],
            update: update_values
          ).insert(attributes)
        rescue NoMethodError => e
          raise unless e.name == :insert_conflict

          begin
            dispatches_dataset.insert(attributes)
          rescue ::Sequel::UniqueConstraintViolation
            dispatches_dataset.where(key: key, fire_time: fire_time).update(update_values)
          end
        end

        find_dispatch(key, fire_time)
      end

      def find_dispatch(key, fire_time)
        self.class.normalize_row(dataset.where(key: key, fire_time: fire_time).first)
      end

      def find_by_key(key)
        query(key: key)
      end

      def find_by_node(node_id)
        query(node_id: node_id)
      end

      def find_by_status(status)
        query(status: status)
      end

      def cleanup(recovery_window: 86_400)
        cutoff_time = Time.now.utc - recovery_window
        dataset.where { fire_time < cutoff_time }.delete
      end

      def self.normalize_row(row)
        return nil unless row

        {
          key: row[:key],
          fire_time: row[:fire_time],
          dispatched_at: row[:dispatched_at],
          node_id: row[:node_id],
          status: row[:status]
        }
      end

      private

      def dataset
        @database.dispatches_dataset
      end

      def query(filters)
        dataset.where(filters).reverse_order(:fire_time).all.map { |row| self.class.normalize_row(row) }
      end
    end
  end
end
