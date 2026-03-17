# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Kaal::Dispatch::DatabaseEngine do
  subject(:engine) { described_class.new(database: db) }

  let(:db) { Sequel.sqlite }

  before do
    db.create_table :kaal_dispatches do
      primary_key :id
      String :key, null: false
      Time :fire_time, null: false
      Time :dispatched_at, null: false
      String :node_id, null: false
      String :status, null: false
    end
    db.add_index :kaal_dispatches, %i[key fire_time], unique: true
    db.add_index :kaal_dispatches, :key
    db.add_index :kaal_dispatches, :node_id
    db.add_index :kaal_dispatches, :status
    db.add_index :kaal_dispatches, :fire_time
  end

  it 'logs, queries, and cleans dispatches' do
    fire_time = Time.now.utc
    older_time = Time.utc(2025, 1, 1, 0, 0, 0)
    engine.log_dispatch('job:a', fire_time, 'node-1')
    engine.log_dispatch('job:b', older_time, 'node-2', 'failed')

    expect(engine.find_dispatch('job:a', fire_time)).to include(node_id: 'node-1')
    expect(engine.find_dispatch('missing', fire_time)).to be_nil
    expect(engine.find_by_key('job:a').length).to eq(1)
    expect(engine.find_by_node('node-2').length).to eq(1)
    expect(engine.find_by_status('failed').length).to eq(1)
    expect(engine.cleanup(recovery_window: 60)).to eq(1)
  end
end
