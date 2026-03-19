# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'

RSpec.describe Kaal::ActiveRecord, integration: :sqlite do
  it 'supports sqlite-backed definition, dispatch, and lock persistence' do
    KaalActiveRecordSupport.with_sqlite_database do |connection|
      registry = described_class::DefinitionRegistry.new(connection:)
      dispatch_registry = described_class::DispatchRegistry.new(connection:)
      adapter = described_class::DatabaseAdapter.new(connection)

      expect(registry.upsert_definition(key: 'job:a', cron: '* * * * *', metadata: { 'a' => 1 })[:metadata]).to eq(a: 1)
      expect(registry.upsert_definition(key: 'job:nil', cron: '* * * * *', metadata: nil)[:metadata]).to eq({})
      expect(registry.disable_definition('job:a')[:enabled]).to be(false)
      first_disabled_at = registry.find_definition('job:a')[:disabled_at]
      expect(first_disabled_at).to be_a(Time)
      expect(registry.upsert_definition(key: 'job:a', cron: '* * * * *', enabled: false)[:disabled_at]).to eq(first_disabled_at)
      expect(registry.enable_definition('job:a')[:enabled]).to be(true)
      expect(registry.enabled_definitions.map { |row| row[:key] }).to eq(%w[job:a job:nil])
      expect(registry.all_definitions.map { |row| row[:key] }).to eq(%w[job:a job:nil])
      expect(registry.find_definition('missing')).to be_nil
      expect(registry.remove_definition('missing')).to be_nil
      expect(registry.remove_definition('job:a')).to include(key: 'job:a')
      expect(registry.all_definitions.map { |row| row[:key] }).to eq(['job:nil'])
      registry.upsert_definition(key: 'job:a', cron: '* * * * *')

      fire_time = Time.utc(2026, 1, 1, 0, 0, 0)
      dispatch_registry.log_dispatch('job:a', fire_time, 'node-1')
      expect(dispatch_registry.find_dispatch('job:a', fire_time)).to include(node_id: 'node-1', status: 'dispatched')
      expect(dispatch_registry.find_by_key('job:a').length).to eq(1)
      expect(dispatch_registry.find_by_node('node-1').length).to eq(1)
      expect(dispatch_registry.find_by_status('dispatched').length).to eq(1)
      expect(dispatch_registry.find_dispatch('job:a', Time.utc(2030, 1, 1))).to be_nil
      expect(dispatch_registry.cleanup(recovery_window: 0)).to eq(1)

      expect(adapter.acquire('lock:1', 60)).to be(true)
      expect(adapter.acquire('lock:1', 60)).to be(false)
      expect(adapter.release('lock:1')).to be(true)
      expect(adapter.release('lock:missing')).to be(false)
      expect(adapter.dispatch_registry).to be_a(described_class::DispatchRegistry)
      expect(adapter.definition_registry).to be_a(described_class::DefinitionRegistry)
    end
  end

  it 'falls back to empty metadata when stored json is invalid' do
    KaalActiveRecordSupport.with_sqlite_database do |connection|
      registry = described_class::DefinitionRegistry.new(connection:)
      record = described_class::DefinitionRecord.create!(
        key: 'job:invalid',
        cron: '* * * * *',
        enabled: true,
        source: 'code',
        metadata: '{',
        created_at: Time.now.utc,
        updated_at: Time.now.utc
      )

      expect(registry.send(:normalize, record)[:metadata]).to eq({})
    end
  end
end
