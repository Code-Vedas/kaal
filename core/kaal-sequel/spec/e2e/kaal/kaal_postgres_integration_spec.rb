# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'

RSpec.describe Kaal, integration: :pg do
  it 'persists definitions and dispatches through postgres advisory locks' do
    skip 'DATABASE_URL not set' if ENV['DATABASE_URL'].to_s.empty?
    require 'kaal/sequel'

    key = 'integration:pg'
    namespace = KaalIntegrationSupport.namespace('pg')
    fixed_time = Time.utc(2026, 1, 1, 0, 0, 30)
    allow(Time).to receive(:now).and_return(*Array.new(100, fixed_time))
    lock_keys = []

    KaalIntegrationSupport.with_project_root('pg') do |root|
      KaalIntegrationSupport.reset_database!(ENV.fetch('DATABASE_URL'))
      database = Sequel.connect(ENV.fetch('DATABASE_URL'))
      KaalIntegrationSupport.create_pg_mysql_schema(database)

      KaalIntegrationSupport.write_scheduler(root, key:)
      KaalIntegrationSupport.write_config(root, <<~RUBY)
        require 'kaal/sequel'

        database = Sequel.connect(ENV.fetch('DATABASE_URL'))

        Kaal.configure do |config|
          config.backend = Kaal::Backend::PostgresAdapter.new(database)
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
      lock_keys = job_calls.map do |job_call|
        fire_time = Time.iso8601(job_call[:args].first)
        "#{namespace}:dispatch:#{key}:#{fire_time.to_i}"
      end

      expect(database[:kaal_definitions].count).to eq(1)
      expect(database[:kaal_dispatches].count).to eq(job_calls.length)
    ensure
      lock_keys.each { |lock_key| described_class.backend&.release(lock_key) }
      database&.disconnect
    end
  end
end
