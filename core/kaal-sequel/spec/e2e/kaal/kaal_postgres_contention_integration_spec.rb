# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'

RSpec.describe Kaal, integration: :pg do
  it 'dispatches at most once per fire time under concurrent postgres-backed ticks' do
    connections = []
    inspector = nil
    key = 'contention:pg'
    namespace = KaalIntegrationSupport.namespace('contention-pg')
    base_time = Time.utc(2026, 1, 1, 0, 0, 30)
    fixed_times = KaalContentionSupport.repeated_fire_times(base_time, iterations: 3)
    database_url = ENV.fetch('DATABASE_URL')

    KaalIntegrationSupport.reset_database!(database_url)
    inspector = Sequel.connect(database_url)
    KaalIntegrationSupport.create_pg_mysql_schema(inspector)

    result = KaalContentionSupport.run_threaded_contention(
      fixed_times: fixed_times,
      key: key,
      namespace: namespace,
      node_count: 4,
      backend_factory: lambda { |_index|
        connection = Sequel.connect(database_url)
        connections << connection
        Kaal::Backend::PostgresAdapter.new(connection)
      }
    )

    KaalContentionSupport.assert_single_dispatch_per_iteration!(result)

    expect(inspector[:kaal_dispatches].where(key: key).count).to eq(3)
    result.fetch(:iterations).each do |iteration|
      fire_time = iteration.fetch(:expected_fire_time)
      expect(inspector[:kaal_dispatches].where(key: key, fire_time: fire_time).count).to eq(1)
    end
  ensure
    connections.each(&:disconnect)
    inspector&.disconnect
  end
end
