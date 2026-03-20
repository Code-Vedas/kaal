# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'

RSpec.describe Kaal::ActiveRecord, integration: :mysql do
  it 'supports mysql-backed scheduling through the documented plain-ruby API' do
    skip 'DATABASE_URL not set' if ENV['DATABASE_URL'].to_s.empty?

    key = 'integration:mysql'
    namespace = KaalIntegrationSupport.namespace('activerecord-mysql')
    fixed_time = Time.utc(2026, 1, 1, 0, 0, 30)
    allow(Time).to receive(:now).and_return(*Array.new(100, fixed_time))

    KaalIntegrationSupport.with_project_root('activerecord-mysql') do |root|
      KaalActiveRecordSupport.reset_database!(ENV.fetch('DATABASE_URL'))
      Kaal::ActiveRecord::ConnectionSupport.configure!(ENV.fetch('DATABASE_URL').gsub('\\!', '!'))
      KaalActiveRecordSupport.create_schema!(locks: false)

      KaalIntegrationSupport.write_scheduler(root, key:)
      KaalIntegrationSupport.write_config(root, <<~RUBY)
        require 'kaal/active_record'

        Kaal::ActiveRecord::ConnectionSupport.configure!(ENV.fetch('DATABASE_URL').gsub('\\!', '!'))

        Kaal.configure do |config|
          config.backend = Kaal::ActiveRecord::MySQLAdapter.new
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

      expect(Kaal.backend).to be_a(Kaal::ActiveRecord::MySQLAdapter)
      expect(Kaal::ActiveRecord::DefinitionRecord.count).to eq(1)
      expect(Kaal::ActiveRecord::DispatchRecord.count).to eq(job_calls.length)
    end
  end
end
