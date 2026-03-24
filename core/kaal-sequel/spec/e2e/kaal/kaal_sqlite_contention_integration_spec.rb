# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'

RSpec.describe Kaal, integration: :sqlite do
  it 'dispatches at most once per fire time under concurrent sqlite-backed ticks' do
    key = 'contention:sqlite'
    namespace = KaalIntegrationSupport.namespace('contention-sqlite')
    base_time = Time.utc(2026, 1, 1, 0, 0, 30)
    fixed_times = KaalContentionSupport.repeated_fire_times(base_time, iterations: 3)
    connections = []

    KaalIntegrationSupport.with_project_root('contention-sqlite') do |root|
      db_dir = File.join(root, 'db')
      db_path = File.join(db_dir, 'kaal.sqlite3')
      FileUtils.mkdir_p(db_dir)
      database = Sequel.sqlite(db_path)
      KaalIntegrationSupport.create_sqlite_schema(database)

      result = KaalContentionSupport.run_threaded_contention(
        fixed_times: fixed_times,
        key: key,
        namespace: namespace,
        node_count: 4,
        backend_factory: lambda { |_index|
          connection = Sequel.connect(adapter: 'sqlite', database: db_path)
          connections << connection
          Kaal::Backend::DatabaseAdapter.new(connection)
        }
      )

      KaalContentionSupport.assert_single_dispatch_per_iteration!(result)

      expect(database[:kaal_dispatches].where(key: key).count).to eq(3)
      expect(database[:kaal_locks].where(Sequel.like(:key, "#{namespace}:dispatch:#{key}:%")).count).to eq(3)

      result.fetch(:iterations).each do |iteration|
        fire_time = iteration.fetch(:expected_fire_time)
        expect(database[:kaal_dispatches].where(key: key, fire_time: fire_time).count).to eq(1)
      end
    ensure
      connections.each(&:disconnect)
      database&.disconnect
    end
  end
end
