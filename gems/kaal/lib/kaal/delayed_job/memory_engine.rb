# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'kaal/delayed_job/registry'
require 'kaal/support/hash_tools'

module Kaal
  module DelayedJob
    # In-memory delayed job store for single-process development and tests.
    class MemoryEngine < Registry
      include Kaal::Support::HashTools

      def initialize
        super
        @jobs = {}
        @mutex = Mutex.new
      end

      def enqueue(job_id:, run_at:, job_class:, args:, queue: nil, **)
        @mutex.synchronize do
          raise DuplicateJobError, "Delayed job #{job_id.inspect} already exists" if @jobs.key?(job_id)

          job = build_job(job_id:, run_at:, job_class:, args:, queue:)
          @jobs[job_id] = job
          deep_dup(job)
        end
      end

      def pop_due(now:, limit:)
        @mutex.synchronize do
          due_jobs = @jobs.values
                          .select { |job| job[:run_at] <= now }
                          .sort_by { |job| job.values_at(:run_at, :job_id) }
                          .first(limit)

          due_jobs.each do |job|
            job_id = job.fetch(:job_id)
            @jobs.delete(job_id)
          end
          due_jobs.map { |job| deep_dup(job) }
        end
      end

      def find_job(job_id)
        @mutex.synchronize { deep_dup(@jobs[job_id]) }
      end

      def all_jobs
        @mutex.synchronize do
          @jobs.values.sort_by { |job| [job[:run_at], job[:job_id]] }.map { |job| deep_dup(job) }
        end
      end

      def clear
        @mutex.synchronize { @jobs.clear }
      end

      def claim_strategy
        :atomic_pop
      end

      private

      def build_job(job_id:, run_at:, job_class:, args:, queue:)
        {
          job_id: job_id,
          run_at: run_at,
          job_class: job_class,
          args: deep_dup(args),
          queue: queue,
          created_at: Time.now.utc
        }
      end
    end
  end
end
