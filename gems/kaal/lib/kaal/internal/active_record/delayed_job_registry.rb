# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'json'
require 'kaal/delayed_job/registry'

module Kaal
  module Internal
    module ActiveRecord
      # Active Record-backed store for delayed jobs.
      class DelayedJobRegistry < Kaal::DelayedJob::Registry
        def initialize(connection: nil, model: DelayedJobRecord, use_skip_locked: false)
          super()
          ConnectionSupport.configure!(connection)
          @model = model
          @use_skip_locked = use_skip_locked
        end

        def enqueue(job_id:, run_at:, job_class:, args:, queue: nil, connection: nil)
          now = Time.now.utc
          attributes = {
            job_id: job_id,
            run_at: run_at,
            job_class: job_class,
            args: JSON.generate(args),
            queue: queue,
            created_at: now
          }

          if connection
            insert_with_connection(connection, attributes)
          else
            @model.create!(attributes)
          end

          normalize(@model.new(attributes))
        rescue ::ActiveRecord::RecordNotUnique
          raise Kaal::DelayedJob::DuplicateJobError, "Delayed job #{job_id.inspect} already exists"
        end

        def pop_due(now:, limit:)
          return pop_due_with_skip_locked(now:, limit:) if @use_skip_locked

          pop_due_with_delete_confirmation(now:, limit:)
        end

        private

        def pop_due_with_skip_locked(now:, limit:)
          @model.transaction do
            due_records = @model.where('run_at <= ?', now).order(:run_at, :job_id).lock('FOR UPDATE SKIP LOCKED').limit(limit).to_a
            job_ids = due_records.map(&:job_id)
            @model.where(job_id: job_ids).delete_all unless job_ids.empty?
            due_records.map { |record| normalize(record) }
          end
        end

        def pop_due_with_delete_confirmation(now:, limit:)
          @model.transaction do
            @model.where('run_at <= ?', now).order(:run_at, :job_id).limit(limit).each_with_object([]) do |record, jobs|
              jobs << normalize(record) if @model.where(job_id: record.job_id).delete_all.positive?
            end
          end
        end

        public

        def find_job(job_id)
          normalize(@model.find_by(job_id: job_id))
        end

        def all_jobs
          @model.order(:run_at, :job_id).map { |record| normalize(record) }
        end

        def claim_strategy
          @use_skip_locked ? :skip_locked : :delete_confirmation
        end

        private

        def insert_with_connection(connection, attributes)
          table_name = @model.table_name
          columns = attributes.keys
          quoted_pairs = columns.map do |column|
            [connection.quote_column_name(column), connection.quote(attributes.fetch(column))]
          end
          quoted_columns = quoted_pairs.map(&:first).join(', ')
          quoted_values = quoted_pairs.map(&:last).join(', ')
          connection.execute("INSERT INTO #{connection.quote_table_name(table_name)} (#{quoted_columns}) VALUES (#{quoted_values})")
        end

        def normalize(record)
          return nil unless record

          {
            job_id: record.job_id,
            run_at: record.run_at,
            job_class: record.job_class,
            args: JSON.parse(record.args || '[]'),
            queue: record.queue,
            created_at: record.created_at
          }
        end
      end
    end
  end
end
