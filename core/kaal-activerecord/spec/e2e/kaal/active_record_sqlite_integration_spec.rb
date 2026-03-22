# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'

RSpec.describe Kaal::ActiveRecord, integration: :sqlite do
  it 'supports sqlite-backed scheduling through the documented plain-ruby API' do
    key = 'integration:sqlite'
    namespace = KaalIntegrationSupport.namespace('activerecord-sqlite')
    fixed_time = Time.utc(2026, 1, 1, 0, 0, 30)
    allow(Time).to receive(:now).and_return(*Array.new(100, fixed_time))

    KaalIntegrationSupport.with_project_root('activerecord-sqlite') do |root|
      db_dir = File.join(root, 'db')
      db_path = File.join(db_dir, 'kaal.sqlite3')
      FileUtils.mkdir_p(db_dir)
      Kaal::ActiveRecord::ConnectionSupport.configure!(adapter: 'sqlite3', database: db_path)
      KaalActiveRecordSupport.create_schema!(locks: true)

      KaalIntegrationSupport.write_scheduler(root, key:)
      KaalIntegrationSupport.write_config(root, <<~RUBY)
        require 'kaal/active_record'

        Kaal::ActiveRecord::ConnectionSupport.configure!(
          adapter: 'sqlite3',
          database: File.expand_path('../db/kaal.sqlite3', __dir__)
        )

        Kaal.configure do |config|
          config.backend = Kaal::ActiveRecord::DatabaseAdapter.new
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

      expect(Kaal.backend).to be_a(Kaal::ActiveRecord::DatabaseAdapter)
      expect(Kaal::ActiveRecord::DefinitionRecord.count).to eq(1)
      expect(Kaal::ActiveRecord::DispatchRecord.count).to eq(job_calls.length)
      expect(Kaal::ActiveRecord::LockRecord.count).to eq(job_calls.length)
    end
  end
end
