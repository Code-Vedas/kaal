# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'

RSpec.describe Kaal, integration: :sqlite do
  it 'persists definitions, dispatches, and locks through sqlite' do
    require 'kaal/sequel'

    key = 'integration:sqlite'
    namespace = KaalIntegrationSupport.namespace('sqlite')
    fixed_time = Time.utc(2026, 1, 1, 0, 0, 30)
    allow(Time).to receive(:now).and_return(*Array.new(100, fixed_time))

    KaalIntegrationSupport.with_project_root('sqlite') do |root|
      db_dir = File.join(root, 'db')
      db_path = File.join(db_dir, 'kaal.sqlite3')
      FileUtils.mkdir_p(db_dir)
      database = Sequel.sqlite(db_path)
      KaalIntegrationSupport.create_sqlite_schema(database)

      KaalIntegrationSupport.write_scheduler(root, key:)
      KaalIntegrationSupport.write_config(root, <<~RUBY)
        require 'kaal/sequel'

        database = Sequel.connect(adapter: 'sqlite', database: File.expand_path('../db/kaal.sqlite3', __dir__))

        Kaal.configure do |config|
          config.backend = Kaal::Backend::DatabaseAdapter.new(database)
          config.namespace = '#{namespace}'
          config.window_lookback = 65
          config.window_lookahead = 0
          config.lease_ttl = 120
          config.enable_log_dispatch_registry = true
          config.enable_dispatch_recovery = false
          config.recovery_startup_jitter = 0
          config.scheduler_config_path = 'config/scheduler.yml'
        end
      RUBY

      job_calls = KaalIntegrationSupport.perform_tick_flow(root, key:)

      expect(database[:kaal_definitions].count).to eq(1)
      expect(database[:kaal_dispatches].count).to eq(job_calls.length)
      expect(database[:kaal_locks].count).to eq(job_calls.length)
    ensure
      database&.disconnect
    end
  end
end
