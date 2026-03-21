# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'json'
require 'kaal/definition/registry'
require 'kaal/definition/persistence_helpers'
require 'kaal/persistence/database'

module Kaal
  module Definition
    # Sequel-backed definition registry persisted in kaal_definitions.
    class DatabaseEngine < Registry
      def initialize(database:)
        super()
        @database = Kaal::Persistence::Database.new(database)
      end

      def upsert_definition(key:, cron:, enabled: true, source: 'code', metadata: {})
        rows = dataset.where(key: key)
        existing = rows.first
        now = Time.now.utc
        payload = {
          key: key,
          cron: cron,
          enabled: enabled,
          source: source,
          metadata: JSON.generate(metadata || {}),
          created_at: existing ? existing[:created_at] : now,
          updated_at: now,
          disabled_at: PersistenceHelpers.disabled_at_for(existing, enabled, now)
        }

        if existing
          rows.update(payload)
        else
          dataset.insert(payload)
        end

        find_definition(key)
      end

      def remove_definition(key)
        rows = dataset.where(key: key)
        row = rows.first
        return nil unless row

        rows.delete
        self.class.normalize_row(row)
      end

      def find_definition(key)
        self.class.normalize_row(dataset.where(key: key).first)
      end

      def all_definitions
        dataset.order(:key).all.map { |row| self.class.normalize_row(row) }
      end

      def enabled_definitions
        dataset.where(enabled: true).order(:key).all.map { |row| self.class.normalize_row(row) }
      end

      def self.normalize_row(row)
        return nil unless row

        {
          key: row[:key],
          cron: row[:cron],
          enabled: row[:enabled] ? true : false,
          source: row[:source],
          metadata: PersistenceHelpers.parse_metadata(row[:metadata]),
          created_at: row[:created_at],
          updated_at: row[:updated_at],
          disabled_at: row[:disabled_at]
        }
      end

      private

      def dataset
        @database.definitions_dataset
      end
    end
  end
end
