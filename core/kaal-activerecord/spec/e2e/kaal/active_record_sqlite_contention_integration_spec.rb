# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'

RSpec.describe Kaal::ActiveRecord, integration: :sqlite do
  it 'dispatches at most once per fire time under concurrent sqlite-backed ticks' do
    key = 'contention:activerecord-sqlite'
    namespace = KaalIntegrationSupport.namespace('contention-activerecord-sqlite')
    base_time = Time.utc(2026, 1, 1, 0, 0, 30)
    fixed_times = KaalContentionSupport.repeated_fire_times(base_time, iterations: 3)

    KaalActiveRecordSupport.with_sqlite_database do |connection|
      result = KaalContentionSupport.run_threaded_contention(
        fixed_times: fixed_times,
        key: key,
        namespace: namespace,
        node_count: 4,
        backend_factory: ->(_index) { Kaal::ActiveRecord::DatabaseAdapter.new(connection) }
      )

      KaalContentionSupport.assert_single_dispatch_per_iteration!(result)

      expect(Kaal::ActiveRecord::DispatchRecord.where(key: key).count).to eq(3)
      expect(Kaal::ActiveRecord::LockRecord.where('key LIKE ?', "#{namespace}:dispatch:#{key}:%").count).to eq(3)

      result.fetch(:iterations).each do |iteration|
        fire_time = iteration.fetch(:expected_fire_time)
        expect(Kaal::ActiveRecord::DispatchRecord.where(key: key, fire_time: fire_time).count).to eq(1)
      end
    end
  end
end
