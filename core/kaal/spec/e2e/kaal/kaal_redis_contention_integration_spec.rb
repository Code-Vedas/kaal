# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'
require 'redis'

RSpec.describe Kaal, integration: :redis do
  it 'dispatches at most once per fire time under concurrent redis-backed ticks' do
    redis = nil
    clients = []
    key = 'contention:redis'
    namespace = KaalIntegrationSupport.namespace('contention-redis')
    base_time = Time.utc(2026, 1, 1, 0, 0, 30)
    fixed_times = KaalContentionSupport.repeated_fire_times(base_time, iterations: 3)
    redis = Redis.new(url: ENV.fetch('REDIS_URL'))

    result = KaalContentionSupport.run_threaded_contention(
      fixed_times: fixed_times,
      key: key,
      namespace: namespace,
      node_count: 4,
      backend_factory: lambda { |_index|
        client = Redis.new(url: ENV.fetch('REDIS_URL'))
        clients << client
        wrapped = KaalIntegrationSupport::RedisClientWrapper.new(client)
        Kaal::Backend::RedisAdapter.new(wrapped, namespace: namespace)
      }
    )

    KaalContentionSupport.assert_single_dispatch_per_iteration!(result)

    expect(redis.scan_each(match: "#{namespace}:dispatch:#{key}:*").to_a.size).to eq(3)
    expect(redis.scan_each(match: "#{namespace}:cron_dispatch:#{key}:*").to_a.size).to eq(3)

    engine = Kaal::Dispatch::RedisEngine.new(redis, namespace: namespace)
    result.fetch(:iterations).each do |iteration|
      fire_time = iteration.fetch(:expected_fire_time)
      expect(engine.find_dispatch(key, fire_time)).to include(status: 'dispatched')
    end
  ensure
    redis&.scan_each(match: "#{namespace}:*") { |redis_key| redis.del(redis_key) }
    clients.each(&:close)
    redis&.close
  end
end
