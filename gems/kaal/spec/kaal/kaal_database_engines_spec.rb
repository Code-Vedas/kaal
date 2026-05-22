# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'
require 'kaal/definition/database_engine'
require 'kaal/dispatch/database_engine'

Kaal::Sequel.require_sequel!

RSpec.describe Kaal do
  let(:db) { Sequel.sqlite }

  before do
    db.create_table :kaal_definitions do
      primary_key :id
      String :key, null: false
      String :cron, null: false
      TrueClass :enabled, null: false, default: true
      String :source, null: false
      String :metadata, text: true, null: false, default: '{}'
      Time :disabled_at
      Time :created_at, null: false
      Time :updated_at, null: false
    end
    db.add_index :kaal_definitions, :key, unique: true

    db.create_table :kaal_dispatches do
      primary_key :id
      String :key, null: false
      Time :fire_time, null: false
      Time :dispatched_at, null: false
      String :node_id, null: false
      String :status, null: false
    end
    db.add_index :kaal_dispatches, %i[key fire_time], unique: true

    db.create_table :kaal_delayed_jobs do
      primary_key :id
      String :job_id, null: false
      Time :run_at, null: false
      String :job_class, null: false
      String :args, text: true, null: false, default: '[]'
      String :queue
      Time :created_at, null: false
    end
  end

  describe Kaal::Definition::DatabaseEngine do
    subject(:engine) { described_class.new(database: db) }

    it 'upserts, finds, lists, and removes persisted definitions' do
      definition = engine.upsert_definition(key: 'job:a', cron: '* * * * *', enabled: true, source: 'code', metadata: { 'a' => 1 })
      engine.upsert_definition(key: 'job:b', cron: '* * * * *', enabled: false, source: 'code', metadata: {})

      expect(definition).to include(key: 'job:a')
      expect(engine.find_definition('job:a')).to include(metadata: { a: 1 })
      expect(engine.enabled_definitions.map { |row| row[:key] }).to eq(['job:a'])
      expect(engine.all_definitions.map { |row| row[:key] }).to eq(%w[job:a job:b])
      expect(engine.remove_definition('job:a')).to include(key: 'job:a')
      expect(described_class.normalize_row(nil)).to be_nil
    end
  end

  describe Kaal::Dispatch::DatabaseEngine do
    subject(:engine) { described_class.new(database: db, namespace: 'ops') }

    let(:fire_time) { Time.utc(2026, 1, 1, 0, 0, 0) }

    it 'logs, updates, finds, queries, and cleans dispatches' do
      engine.log_dispatch('job:a', fire_time, 'node-1', 'dispatched')
      engine.log_dispatch('job:a', fire_time, 'node-2', 'failed')
      engine.log_dispatch('job:b', fire_time + 60, 'node-1', 'dispatched')

      expect(engine.find_dispatch('job:a', fire_time)).to include(node_id: 'node-2', status: 'failed')
      expect(engine.find_by_key('job:a').length).to eq(1)
      expect(engine.find_by_node('node-1').map { |row| row[:key] }).to eq(['job:b'])
      expect(engine.find_by_status('failed').map { |row| row[:key] }).to eq(['job:a'])
      expect(engine.cleanup(recovery_window: 30)).to eq(2)
      expect(described_class.normalize_row(nil, namespace: 'ops')).to be_nil
      expect(described_class.strip_namespace('ops:job:a', namespace: 'ops')).to eq('job:a')
    end
  end

  it 'exposes every sequel dataset helper' do
    persistence = Kaal::Persistence::Database.new(db)

    expect(persistence.definitions_dataset).to be_a(Sequel::Dataset)
    expect(persistence.dispatches_dataset).to be_a(Sequel::Dataset)
    expect(persistence.delayed_jobs_dataset).to be_a(Sequel::Dataset)
    expect(persistence.locks_dataset).to be_a(Sequel::Dataset)
  end
end
