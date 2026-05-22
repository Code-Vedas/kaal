# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'

Kaal::Sequel.require_sequel!

RSpec.describe Kaal do
  let(:run_at) { Time.utc(2026, 1, 1, 0, 0, 0) }

  before do
    described_class.delayed_job_allowed_class_prefixes = []

    stub_const('DelayedJobSpecPerformLaterTarget', Class.new do
      def self.perform_later(*) = nil
    end)

    stub_const('DelayedJobSpecQueueTarget', Class.new do
      def self.set(queue:)
        Class.new do
          define_singleton_method(:perform_later) { |*| queue }
        end
      end
    end)

    stub_const('DelayedJobSpecInvalidTarget', Class.new)
  end

  it 'enqueues delayed jobs through the public api on the memory backend' do
    described_class.backend = Kaal::Backend::MemoryAdapter.new

    job = described_class.enqueue_at(
      at: run_at,
      job_class: DelayedJobSpecPerformLaterTarget,
      args: ['a'],
      queue: nil,
      job_id: 'job:a'
    )

    expect(job).to include(job_id: 'job:a', job_class: 'DelayedJobSpecPerformLaterTarget', args: ['a'])
    expect(described_class.backend.delayed_store.find_job('job:a')).to include(job_id: 'job:a')
  end

  it 'rejects invalid delayed job arguments and duplicates' do
    described_class.backend = Kaal::Backend::MemoryAdapter.new

    expect do
      described_class.enqueue_at(at: run_at, job_class: DelayedJobSpecPerformLaterTarget, args: [], queue: nil, job_id: ' ')
    end.to raise_error(ArgumentError, /job_id cannot be blank/)

    expect do
      described_class.enqueue_at(at: run_at, job_class: DelayedJobSpecPerformLaterTarget, args: 'bad', queue: nil, job_id: 'job:a')
    end.to raise_error(ArgumentError, /args must be an array/)

    broken_time = Object.new
    broken_time.define_singleton_method(:to_time) { raise NoMethodError, 'boom' }
    expect do
      described_class.enqueue_at(at: broken_time, job_class: DelayedJobSpecPerformLaterTarget, args: [], queue: nil, job_id: 'job:a')
    end.to raise_error(ArgumentError, /at must be a Time or time-like value/)

    expect do
      described_class.enqueue_at(at: run_at, job_class: DelayedJobSpecPerformLaterTarget, args: [], queue: ' ', job_id: 'job:a')
    end.to raise_error(ArgumentError, /queue cannot be blank/)

    expect do
      described_class.enqueue_at(at: run_at, job_class: DelayedJobSpecInvalidTarget, args: [], queue: nil, job_id: 'job:a')
    end.to raise_error(Kaal::SchedulerConfigError, /must respond to/)

    described_class.enqueue_at(at: run_at, job_class: DelayedJobSpecPerformLaterTarget, args: [], queue: nil, job_id: 'job:a')
    expect do
      described_class.enqueue_at(at: run_at, job_class: DelayedJobSpecPerformLaterTarget, args: [], queue: nil, job_id: 'job:a')
    end.to raise_error(Kaal::DelayedJob::DuplicateJobError)
  end

  it 'raises when the configured backend does not support delayed jobs' do
    described_class.backend = nil

    expect do
      described_class.enqueue_at(at: run_at, job_class: DelayedJobSpecPerformLaterTarget, args: [], queue: nil, job_id: 'job:a')
    end.to raise_error(ArgumentError, /does not support delayed jobs/)
  end

  it 'rejects delayed jobs outside the configured allow-list' do
    described_class.backend = Kaal::Backend::MemoryAdapter.new
    described_class.delayed_job_allowed_class_prefixes = ['Allowed::']

    expect do
      described_class.enqueue_at(
        at: run_at,
        job_class: DelayedJobSpecPerformLaterTarget,
        args: [],
        queue: nil,
        job_id: 'job:blocked'
      )
    end.to raise_error(Kaal::SchedulerConfigError, /not allowed/)
  end

  it 'accepts time-like inputs' do
    described_class.backend = Kaal::Backend::MemoryAdapter.new
    time_like = Struct.new(:value) do
      def to_time
        value
      end
    end.new(run_at)

    job = described_class.enqueue_at(
      at: time_like,
      job_class: DelayedJobSpecPerformLaterTarget,
      args: [],
      queue: nil,
      job_id: 'job:time-like'
    )

    expect(job).to include(run_at: run_at)
  end

  it 'persists delayed jobs through sequel and rolls back with the host transaction' do
    db = Sequel.sqlite
    db.create_table :kaal_delayed_jobs do
      primary_key :id
      String :job_id, null: false
      Time :run_at, null: false
      String :job_class, null: false
      String :args, text: true, null: false, default: '[]'
      String :queue
      Time :created_at, null: false
    end
    db.add_index :kaal_delayed_jobs, :job_id, unique: true
    db.add_index :kaal_delayed_jobs, :run_at

    described_class.backend = Kaal::Backend::SQLite.new(database: db)

    described_class.enqueue_at(at: run_at, job_class: DelayedJobSpecQueueTarget, args: ['a'], queue: 'low', job_id: 'job:a')
    expect(described_class.backend.delayed_store.find_job('job:a')).to include(queue: 'low')

    db.transaction do
      described_class.enqueue_at(
        at: run_at,
        job_class: DelayedJobSpecPerformLaterTarget,
        args: ['b'],
        queue: nil,
        job_id: 'job:rollback',
        connection: db
      )
      raise Sequel::Rollback
    end

    expect(described_class.backend.delayed_store.find_job('job:rollback')).to be_nil
  end

  it 'persists delayed jobs through active record and rolls back with the supplied live connection' do
    KaalActiveRecordSupport.with_sqlite_database do |connection|
      described_class.backend = Kaal::Backend::SQLite.new(connection: connection)
      live_connection = Kaal::Internal::ActiveRecord::BaseRecord.connection

      described_class.enqueue_at(
        at: run_at,
        job_class: DelayedJobSpecPerformLaterTarget,
        args: ['a'],
        queue: nil,
        job_id: 'job:a'
      )
      expect(described_class.backend.delayed_store.find_job('job:a')).to include(job_id: 'job:a')

      live_connection.transaction do
        described_class.enqueue_at(
          at: run_at,
          job_class: DelayedJobSpecPerformLaterTarget,
          args: ['b'],
          queue: nil,
          job_id: 'job:rollback',
          connection: live_connection
        )
        raise ActiveRecord::Rollback
      end

      expect(described_class.backend.delayed_store.find_job('job:rollback')).to be_nil
    end
  end
end
