# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'

RSpec.describe Kaal::ActiveRecord, integration: :mysql do
  it 'supports mysql-backed definition, dispatch, and named-lock persistence' do
    skip 'DATABASE_URL not set' if ENV['DATABASE_URL'].to_s.empty?

    KaalActiveRecordSupport.reset_database!(ENV.fetch('DATABASE_URL'))
    KaalActiveRecordSupport.connect!(ENV.fetch('DATABASE_URL'))
    KaalActiveRecordSupport.create_schema!(locks: false)

    registry = described_class::DefinitionRegistry.new
    dispatch_registry = described_class::DispatchRegistry.new
    adapter = described_class::MySQLAdapter.new

    expect(registry.upsert_definition(key: 'job:mysql', cron: '* * * * *', metadata: { backend: 'mysql' })[:metadata]).to eq(
      backend: 'mysql'
    )
    expect(registry.find_definition('job:mysql')).to include(enabled: true, source: 'code')

    fire_time = Time.utc(2026, 1, 1, 0, 0, 0)
    dispatch_registry.log_dispatch('job:mysql', fire_time, 'node-mysql')
    expect(dispatch_registry.find_dispatch('job:mysql', fire_time)).to include(node_id: 'node-mysql', status: 'dispatched')

    lock_key = 'lock:mysql'
    expect(adapter.acquire(lock_key, 60)).to be(true)
    expect(adapter.acquire(lock_key, 60)).to be(false)
    expect(adapter.release(lock_key)).to be(true)
    expect(adapter.release(lock_key)).to be(false)
    expect(adapter.dispatch_registry).to be_a(described_class::DispatchRegistry)
    expect(adapter.definition_registry).to be_a(described_class::DefinitionRegistry)
  end
end
