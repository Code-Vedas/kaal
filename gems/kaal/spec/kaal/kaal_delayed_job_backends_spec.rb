# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'
require 'kaal/delayed_job/database_engine'

Kaal::Sequel.require_sequel!

RSpec.describe Kaal do
  let(:run_at) { Time.utc(2026, 1, 1, 0, 0, 0) }

  describe Kaal::DelayedJob::DatabaseEngine do
    subject(:engine) { described_class.new(database: db) }

    let(:db) { Sequel.sqlite }

    before do
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
    end

    it 'stores, lists, finds, and removes due jobs' do
      job = engine.enqueue(job_id: 'job:a', run_at: run_at, job_class: 'ExampleJob', args: ['a'], queue: 'low')
      engine.enqueue(job_id: 'job:b', run_at: run_at + 60, job_class: 'ExampleJob', args: [], queue: nil)

      expect(job).to include(job_id: 'job:a', args: ['a'], queue: 'low')
      expect(engine.find_job('missing')).to be_nil
      expect(engine.all_jobs.map { |delayed_job| delayed_job[:job_id] }).to eq(%w[job:a job:b])
      expect(engine.pop_due(now: run_at, limit: 10).map { |delayed_job| delayed_job[:job_id] }).to eq(['job:a'])
      expect(engine.pop_due(now: run_at, limit: 10)).to eq([])
    end

    it 'reports its delayed-job claim strategy' do
      expect(engine.claim_strategy).to eq(:delete_confirmation)
      expect(described_class.new(database: db, use_skip_locked: true).claim_strategy).to eq(:skip_locked)
    end

    it 'rejects duplicates and normalizes rows' do
      engine.enqueue(job_id: 'job:a', run_at: run_at, job_class: 'ExampleJob', args: [], queue: nil)

      expect do
        engine.enqueue(job_id: 'job:a', run_at: run_at, job_class: 'ExampleJob', args: [], queue: nil)
      end.to raise_error(Kaal::DelayedJob::DuplicateJobError)

      expect(described_class.normalize_row(nil)).to be_nil
    end

    it 'skips malformed arg payloads instead of raising' do
      db[:kaal_delayed_jobs].insert(
        job_id: 'job:bad',
        run_at: run_at,
        job_class: 'ExampleJob',
        args: '{',
        queue: nil,
        created_at: run_at
      )

      expect(described_class.normalize_row(db[:kaal_delayed_jobs].first(job_id: 'job:bad'))).to be_nil
      expect(engine.find_job('job:bad')).to be_nil
      expect(engine.all_jobs).to eq([])
      expect(engine.pop_due(now: run_at, limit: 10)).to eq([])
    end

    it 'claims due jobs through the skip-locked path when enabled' do
      dataset = instance_double(Sequel::Dataset)
      locked_dataset = instance_double(Sequel::Dataset)
      connection = instance_double(Sequel::Database)
      persistence_database = instance_double(Kaal::Persistence::Database, connection:)
      allow(Kaal::Persistence::Database).to receive(:new).with(connection).and_return(persistence_database)
      engine = described_class.new(database: connection, use_skip_locked: true)
      due_rows = [
        { job_id: 'job:a', run_at:, job_class: 'ExampleJob', args: '["a"]', queue: nil, created_at: run_at }
      ]

      allow(connection).to receive(:transaction).and_yield
      allow(connection).to receive(:[]).with(:kaal_delayed_jobs).and_return(dataset)
      allow(dataset).to receive_messages(where: dataset, for_update: locked_dataset)
      allow(dataset).to receive(:order).with(:run_at, :job_id).and_return(dataset)
      allow(locked_dataset).to receive_messages(skip_locked: locked_dataset, all: due_rows)
      allow(locked_dataset).to receive(:limit).with(5).and_return(locked_dataset)
      allow(dataset).to receive(:delete)

      jobs = engine.pop_due(now: run_at, limit: 5)

      expect(jobs).to eq(
        [{ job_id: 'job:a', run_at:, job_class: 'ExampleJob', args: ['a'], queue: nil, created_at: run_at }]
      )
      expect(dataset).to have_received(:delete)
    end

    it 'deletes malformed claimed rows in the skip-locked path' do
      dataset = instance_double(Sequel::Dataset)
      locked_dataset = instance_double(Sequel::Dataset)
      delete_dataset = instance_double(Sequel::Dataset)
      connection = instance_double(Sequel::Database)
      persistence_database = instance_double(Kaal::Persistence::Database, connection:)
      allow(Kaal::Persistence::Database).to receive(:new).with(connection).and_return(persistence_database)
      engine = described_class.new(database: connection, use_skip_locked: true)
      due_rows = [
        { job_id: 'job:bad', run_at:, job_class: 'ExampleJob', args: '{', queue: nil, created_at: run_at }
      ]

      allow(connection).to receive(:transaction).and_yield
      allow(connection).to receive(:[]).with(:kaal_delayed_jobs).and_return(dataset)
      allow(dataset).to receive(:where).with(job_id: ['job:bad']).and_return(delete_dataset)
      allow(dataset).to receive(:where).with(no_args).and_return(dataset)
      allow(dataset).to receive_messages(order: dataset, for_update: locked_dataset)
      allow(locked_dataset).to receive_messages(skip_locked: locked_dataset, all: due_rows)
      allow(locked_dataset).to receive(:limit).with(5).and_return(locked_dataset)
      allow(delete_dataset).to receive(:delete)

      jobs = engine.pop_due(now: run_at, limit: 5)

      expect(jobs).to eq([])
      expect(delete_dataset).to have_received(:delete)
    end
  end

  describe Kaal::DelayedJob::RedisEngine do
    subject(:engine) { described_class.new(redis, namespace: 'ops') }

    let(:redis) do
      Struct.new(:hashes, :sorted_sets) do
        def eval(_script, keys:, argv:)
          if argv.length == 3
            enqueue_into_sorted_set(keys:, argv:)
          else
            pop_due_from_sorted_set(keys:, argv:)
          end
        end

        def hget(key, field)
          hashes[key][field]
        end

        def hset(key, field, value)
          hashes[key][field] = value
        end

        def zadd(key, score, member)
          sorted_sets[key][member] = score
        end

        def zrange(key, _start_index, _end_index)
          sorted_sets[key].sort_by { |member, score| [score, member] }.map(&:first)
        end

        private

        def enqueue_into_sorted_set(keys:, argv:)
          payloads_key, schedule_key = keys
          job_id, payload, score = argv
          return 0 if hashes[payloads_key].key?(job_id)

          hashes[payloads_key][job_id] = payload
          sorted_sets[schedule_key][job_id] = score.to_f
          1
        end

        def pop_due_from_sorted_set(keys:, argv:)
          payloads_key, schedule_key = keys
          now, limit = argv
          due_job_ids = sorted_sets[schedule_key]
                        .select { |_member, score| score <= now.to_f }
                        .sort_by { |member, score| [score, member] }
                        .first(limit.to_i)
                        .map(&:first)

          due_job_ids.filter_map do |job_id|
            next unless sorted_sets[schedule_key].delete(job_id)

            hashes[payloads_key].delete(job_id)
          end
        end
      end.new(
        Hash.new { |hash, key| hash[key] = {} },
        Hash.new { |hash, key| hash[key] = {} }
      )
    end

    it 'returns empty sets for missing due jobs and invalid payloads' do
      expect(engine.find_job('missing')).to be_nil
      expect(engine.pop_due(now: run_at, limit: 10)).to eq([])

      redis.hset('ops:delayed_jobs:payloads', 'bad', '{')
      redis.zadd('ops:delayed_jobs:schedule', run_at.to_f, 'bad')
      expect(engine.all_jobs).to eq([])
      expect(described_class.deserialize(nil)).to be_nil
    end

    it 'reports its delayed-job claim strategy' do
      expect(engine.claim_strategy).to eq(:atomic_pop)
    end
  end
end
