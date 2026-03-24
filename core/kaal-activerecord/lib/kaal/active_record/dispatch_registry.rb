# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'kaal/dispatch/registry'

module Kaal
  module ActiveRecord
    # Active Record-backed registry for dispatch audit records.
    class DispatchRegistry < Kaal::Dispatch::Registry
      def initialize(connection: nil, model: DispatchRecord, namespace: nil)
        super()
        ConnectionSupport.configure!(connection)
        @model = model
        @namespace = namespace
      end

      def log_dispatch(key, fire_time, node_id, status = 'dispatched')
        record = @model.find_or_initialize_by(key: namespaced_key(key), fire_time: fire_time)
        record.dispatched_at = Time.now.utc
        record.node_id = node_id
        record.status = status
        record.save!
        normalize(record)
      end

      def find_dispatch(key, fire_time)
        normalize(@model.find_by(key: namespaced_key(key), fire_time: fire_time))
      end

      def find_by_key(key)
        query(key: namespaced_key(key))
      end

      def find_by_node(node_id)
        query(node_id: node_id)
      end

      def find_by_status(status)
        query(status: status)
      end

      def cleanup(recovery_window: 86_400)
        cutoff_time = Time.now.utc - recovery_window
        cleanup_scope.where(fire_time: ...cutoff_time).delete_all
      end

      private

      def query(filters)
        query_scope(filters).order(fire_time: :desc).map { |record| normalize(record) }
      end

      def namespaced_key(key)
        "#{namespace_prefix}#{key}"
      end

      def normalize(record)
        return nil unless record

        {
          key: strip_namespace(record.key),
          fire_time: record.fire_time,
          dispatched_at: record.dispatched_at,
          node_id: record.node_id,
          status: record.status
        }
      end

      def strip_namespace(key)
        key.delete_prefix(namespace_prefix)
      end

      def query_scope(filters)
        relation = @model.where(filters)
        return relation if filters.key?(:key)

        namespace_scope(relation)
      end

      def cleanup_scope
        namespace_scope(@model)
      end

      def namespace_scope(relation)
        return relation if namespace_prefix.empty?

        relation.where('key LIKE ?', "#{namespace_prefix}%")
      end

      def namespace_prefix
        @namespace.to_s.empty? ? '' : "#{@namespace}:"
      end
    end
  end
end
