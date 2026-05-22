# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'json'
require 'kaal/delayed_job/registry'
require 'kaal/persistence/database'

module Kaal
  module DelayedJob
    # Sequel-backed delayed-job store persisted in kaal_delayed_jobs.
    class DatabaseEngine < Registry
      def initialize(database:, use_skip_locked: false)
        super()
        @database = Kaal::Persistence::Database.new(database)
        @use_skip_locked = use_skip_locked
      end

      def enqueue(job_id:, run_at:, job_class:, args:, queue: nil, connection: nil)
        now = Time.now.utc
        payload = {
          job_id: job_id,
          run_at: run_at,
          job_class: job_class,
          args: JSON.generate(args),
          queue: queue,
          created_at: now
        }

        dataset_for(connection).insert(payload)
        self.class.normalize_row(payload)
      rescue ::Sequel::UniqueConstraintViolation
        raise DuplicateJobError, "Delayed job #{job_id.inspect} already exists"
      end

      def pop_due(now:, limit:)
        return pop_due_with_skip_locked(now:, limit:) if @use_skip_locked

        pop_due_with_delete_confirmation(now:, limit:)
      end

      def find_job(job_id, connection: @database.connection)
        self.class.normalize_row(connection[:kaal_delayed_jobs].where(job_id: job_id).first)
      end

      def all_jobs
        connection[:kaal_delayed_jobs].order(:run_at, :job_id).all.map { |row| self.class.normalize_row(row) }
      end

      def claim_strategy
        @use_skip_locked ? :skip_locked : :delete_confirmation
      end

      def self.normalize_row(row)
        return nil unless row

        {
          job_id: row[:job_id],
          run_at: row[:run_at],
          job_class: row[:job_class],
          args: JSON.parse(row[:args] || '[]'),
          queue: row[:queue],
          created_at: row[:created_at]
        }
      end

      private

      def pop_due_with_skip_locked(now:, limit:)
        connection.transaction do
          delayed_jobs_dataset = connection[:kaal_delayed_jobs]
          due_rows = delayed_jobs_dataset.where { run_at <= now }.order(:run_at, :job_id).for_update.skip_locked.limit(limit).all
          normalized_jobs = due_rows.map { |row| self.class.normalize_row(row) }
          job_ids = normalized_jobs.map { |job| job[:job_id] }
          delayed_jobs_dataset.where(job_id: job_ids).delete unless job_ids.empty?
          normalized_jobs
        end
      end

      def pop_due_with_delete_confirmation(now:, limit:)
        connection.transaction do
          delayed_jobs_dataset = connection[:kaal_delayed_jobs]
          due_rows = delayed_jobs_dataset.where { run_at <= now }.order(:run_at, :job_id).limit(limit).all
          due_rows.each_with_object([]) do |row, jobs|
            deleted = delayed_jobs_dataset.where(job_id: row[:job_id]).delete
            jobs << self.class.normalize_row(row) if deleted.positive?
          end
        end
      end

      def dataset_for(connection)
        return dataset unless connection

        Kaal::Persistence::Database.new(connection).delayed_jobs_dataset
      end

      def dataset
        @database.delayed_jobs_dataset
      end

      def connection
        @database.connection
      end
    end
  end
end
