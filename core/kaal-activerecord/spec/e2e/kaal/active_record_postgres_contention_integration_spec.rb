# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'

RSpec.describe Kaal::ActiveRecord, integration: :pg do
  it 'dispatches at most once per fire time under concurrent postgres-backed ticks' do
    key = 'contention:activerecord-pg'
    namespace = KaalIntegrationSupport.namespace('contention-activerecord-pg')
    base_time = Time.utc(2026, 1, 1, 0, 0, 30)
    fixed_times = KaalContentionSupport.repeated_fire_times(base_time, iterations: 3)
    database_url = ENV.fetch('DATABASE_URL')

    KaalActiveRecordSupport.reset_database!(database_url)
    KaalActiveRecordSupport.connect!(database_url)
    KaalActiveRecordSupport.create_schema!(locks: false)

    result = KaalContentionSupport.run_threaded_contention(
      fixed_times: fixed_times,
      key: key,
      namespace: namespace,
      node_count: 4,
      backend_factory: ->(_index) { Kaal::ActiveRecord::PostgresAdapter.new(database_url) }
    )

    KaalContentionSupport.assert_single_dispatch_per_iteration!(result)

    expect(Kaal::ActiveRecord::DispatchRecord.where(key: key).count).to eq(3)
    result.fetch(:iterations).each do |iteration|
      fire_time = iteration.fetch(:expected_fire_time)
      expect(Kaal::ActiveRecord::DispatchRecord.where(key: key, fire_time: fire_time).count).to eq(1)
    end
  end
end
