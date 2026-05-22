# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'
Kaal::ActiveRecord.require_activerecord!
require 'kaal/internal/active_record'

RSpec.describe Kaal::Internal::ActiveRecord::DelayedJobRegistry do
  subject(:registry) { described_class.new }

  let(:run_at) { Time.utc(2026, 1, 1, 0, 0, 0) }

  around do |example|
    KaalActiveRecordSupport.with_sqlite_database do |connection|
      described_class.new(connection: connection)
      example.run
    end
  end

  it 'stores, fetches, orders, and removes due jobs' do
    registry.enqueue(job_id: 'job:b', run_at: run_at, job_class: 'ExampleJob', args: ['b'], queue: nil)
    registry.enqueue(job_id: 'job:a', run_at: run_at, job_class: 'ExampleJob', args: ['a'], queue: 'low')

    expect(registry.find_job('job:a')).to include(queue: 'low')
    expect(registry.all_jobs.map { |job| job[:job_id] }).to eq(%w[job:a job:b])
    expect(registry.pop_due(now: run_at, limit: 1).map { |job| job[:job_id] }).to eq(['job:a'])
    expect(registry.pop_due(now: run_at, limit: 10).map { |job| job[:job_id] }).to eq(['job:b'])
    expect(registry.pop_due(now: run_at, limit: 10)).to eq([])
  end

  it 'reports its delayed-job claim strategy' do
    expect(registry.claim_strategy).to eq(:delete_confirmation)
    expect(described_class.new(use_skip_locked: true).claim_strategy).to eq(:skip_locked)
  end

  it 'rejects duplicates and supports inserts through a live connection' do
    registry.enqueue(job_id: 'job:a', run_at: run_at, job_class: 'ExampleJob', args: [], queue: nil)

    expect do
      registry.enqueue(job_id: 'job:a', run_at: run_at, job_class: 'ExampleJob', args: [], queue: nil)
    end.to raise_error(Kaal::DelayedJob::DuplicateJobError)

    live_connection = Kaal::Internal::ActiveRecord::BaseRecord.connection
    record = registry.enqueue(
      job_id: 'job:b',
      run_at: run_at,
      job_class: 'ExampleJob',
      args: ['b'],
      queue: nil,
      connection: live_connection
    )

    expect(record).to include(job_id: 'job:b', args: ['b'])
  end

  it 'uses a skip-locked claim query when enabled' do
    relation = instance_double(ActiveRecord::Relation)
    delete_relation = instance_double(ActiveRecord::Relation)
    model = class_double(Kaal::Internal::ActiveRecord::DelayedJobRecord)
    record = double(
      job_id: 'job:a',
      run_at:,
      job_class: 'ExampleJob',
      args: '["a"]',
      queue: nil,
      created_at: run_at
    )
    registry = described_class.new(model:, use_skip_locked: true)

    allow(model).to receive(:transaction).and_yield
    allow(model).to receive(:where).with('run_at <= ?', run_at).and_return(relation)
    allow(relation).to receive(:order).with(:run_at, :job_id).and_return(relation)
    allow(relation).to receive(:lock).with('FOR UPDATE SKIP LOCKED').and_return(relation)
    allow(relation).to receive(:limit).with(2).and_return(relation)
    allow(relation).to receive(:to_a).and_return([record])
    allow(model).to receive(:where).with(job_id: ['job:a']).and_return(delete_relation)
    allow(delete_relation).to receive(:delete_all).and_return(1)

    jobs = registry.pop_due(now: run_at, limit: 2)

    expect(jobs).to eq(
      [{ job_id: 'job:a', run_at:, job_class: 'ExampleJob', args: ['a'], queue: nil, created_at: run_at }]
    )
  end
end
