# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'

RSpec.describe Kaal::Definition::DatabaseEngine do
  subject(:engine) { described_class.new(database: db) }

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
  end

  it 'upserts and reads definitions' do
    engine.upsert_definition(key: 'job:one', cron: '*/5 * * * *', enabled: true, source: 'code', metadata: { owner: 'ops' })

    definition = engine.find_definition('job:one')
    expect(definition).to include(key: 'job:one', cron: '*/5 * * * *', enabled: true, source: 'code')
    expect(definition[:metadata]).to eq(owner: 'ops')
  end

  it 'tracks disabled_at when a definition is disabled' do
    engine.upsert_definition(key: 'job:one', cron: '*/5 * * * *', enabled: true, source: 'code', metadata: {})
    engine.disable_definition('job:one')

    definition = engine.find_definition('job:one')
    expect(definition[:enabled]).to be(false)
    expect(definition[:disabled_at]).to be_a(Time)
  end

  it 'supports listing, removal, and invalid metadata fallback' do
    engine.upsert_definition(key: 'job:one', cron: '*/5 * * * *', enabled: true, source: 'code', metadata: nil)
    engine.upsert_definition(key: 'job:two', cron: '0 * * * *', enabled: false, source: 'file', metadata: {})
    db[:kaal_definitions].where(key: 'job:two').update(metadata: '{')

    expect(engine.all_definitions.map { |row| row[:key] }).to eq(%w[job:one job:two])
    expect(engine.enabled_definitions.map { |row| row[:key] }).to eq(['job:one'])
    expect(engine.find_definition('job:two')[:metadata]).to eq({})
    expect(engine.remove_definition('job:one')).to include(key: 'job:one')
    expect(engine.remove_definition('missing')).to be_nil
    expect(described_class.normalize_row(nil)).to be_nil
  end
end
