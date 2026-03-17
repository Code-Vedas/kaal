# frozen_string_literal: true

require 'json'
require 'kaal/definition/registry'

module Kaal
  module ActiveRecord
    # Active Record-backed registry for scheduler definitions.
    class DefinitionRegistry < Kaal::Definition::Registry
      def initialize(connection: nil, model: DefinitionRecord)
        super()
        ConnectionSupport.configure!(connection)
        @model = model
      end

      def upsert_definition(key:, cron:, enabled: true, source: 'code', metadata: {})
        record = @model.find_or_initialize_by(key: key)
        now = Time.now.utc
        record.cron = cron
        record.enabled = enabled
        record.source = source
        record.metadata = JSON.generate(metadata || {})
        record.created_at ||= now
        record.updated_at = now
        record.disabled_at = disabled_at_for(record, enabled, now)
        record.save!
        normalize(record)
      end

      def remove_definition(key)
        record = @model.find_by(key: key)
        return nil unless record

        normalized = normalize(record)
        record.destroy!
        normalized
      end

      def find_definition(key)
        normalize(@model.find_by(key: key))
      end

      def all_definitions
        @model.order(:key).map { |record| normalize(record) }
      end

      def enabled_definitions
        @model.where(enabled: true).order(:key).map { |record| normalize(record) }
      end

      private

      def disabled_at_for(record, enabled, now)
        return nil if enabled
        return now unless record.persisted?

        record.disabled_at || now
      end

      def normalize(record)
        return nil unless record

        {
          key: record.key,
          cron: record.cron,
          enabled: record.enabled ? true : false,
          source: record.source,
          metadata: JSON.parse(record.metadata || '{}'),
          created_at: record.created_at,
          updated_at: record.updated_at,
          disabled_at: record.disabled_at
        }
      end
    end
  end
end
