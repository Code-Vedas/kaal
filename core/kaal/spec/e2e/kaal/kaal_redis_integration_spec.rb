# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'
require 'redis'

RSpec.describe Kaal, integration: :redis do
  it 'persists definitions and dispatches through redis' do
    skip 'REDIS_URL not set' if ENV['REDIS_URL'].to_s.empty?

    key = 'integration:redis'
    namespace = KaalIntegrationSupport.namespace('redis')
    fixed_time = Time.utc(2026, 1, 1, 0, 0, 30)
    allow(Time).to receive(:now).and_return(*Array.new(100, fixed_time))
    redis = Redis.new(url: ENV.fetch('REDIS_URL'))

    KaalIntegrationSupport.with_project_root('redis') do |root|
      redis.scan_each(match: "#{namespace}:*") { |redis_key| redis.del(redis_key) }

      KaalIntegrationSupport.write_scheduler(root, key:)
      KaalIntegrationSupport.write_config(root, <<~RUBY)
        require 'kaal'
        require 'redis'

        redis = KaalIntegrationSupport::RedisClientWrapper.new(Redis.new(url: ENV.fetch('REDIS_URL')))

        Kaal.configure do |config|
          config.backend = Kaal::Backend::RedisAdapter.new(redis, namespace: '#{namespace}')
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

      expect(described_class.backend.definition_registry.find_definition(key)).to include(source: 'file', enabled: true)
      job_calls.each do |job_call|
        fire_time = Time.iso8601(job_call[:args].first)
        expect(described_class.backend.dispatch_registry.find_dispatch(key, fire_time)).to include(status: 'dispatched')
      end
    ensure
      redis.scan_each(match: "#{namespace}:*") { |redis_key| redis.del(redis_key) }
      redis.close
    end
  end
end
