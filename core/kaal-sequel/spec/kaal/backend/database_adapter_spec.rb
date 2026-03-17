# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Kaal::Backend::DatabaseAdapter do
  subject(:adapter) { described_class.new(db) }

  let(:db) { Sequel.sqlite }

  before do
    db.create_table :kaal_locks do
      primary_key :id
      String :key, null: false
      Time :acquired_at, null: false
      Time :expires_at, null: false
    end
    db.add_index :kaal_locks, :key, unique: true

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
  end

  it 'acquires a lock once and releases it' do
    expect(adapter.acquire('kaal:dispatch:test:1', 60)).to be(true)
    expect(adapter.acquire('kaal:dispatch:test:1', 60)).to be(false)
    expect(adapter.release('kaal:dispatch:test:1')).to be(true)
  end

  it 'exposes sequel-backed registries' do
    expect(adapter.definition_registry).to be_a(Kaal::Definition::DatabaseEngine)
    expect(adapter.dispatch_registry).to be_a(Kaal::Dispatch::DatabaseEngine)
  end

  it 'wraps lock adapter errors' do
    broken_db = instance_double(
      Kaal::Persistence::Database,
      locks_dataset: instance_double(Sequel::Dataset)
    )
    adapter = described_class.allocate
    adapter.instance_variable_set(:@database, broken_db)
    allow(broken_db.locks_dataset).to receive(:insert).and_raise(StandardError, 'insert boom')
    allow(broken_db.locks_dataset).to receive(:where).and_raise(StandardError, 'delete boom')

    expect { adapter.acquire('kaal:dispatch:test:1', 60) }.to raise_error(Kaal::Backend::LockAdapterError, /Database acquire failed/)
    expect { adapter.release('kaal:dispatch:test:1') }.to raise_error(Kaal::Backend::LockAdapterError, /Database release failed/)
  end
end
