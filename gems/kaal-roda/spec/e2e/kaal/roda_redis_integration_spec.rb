# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'
require 'redis'

RSpec.describe Kaal::Roda, integration: :redis do
  include RodaIntegrationHelpers

  it 'integrates a Roda app through the redis backend' do
    skip 'REDIS_URL not set' if ENV['REDIS_URL'].to_s.empty?

    namespace = "kaal-roda-test:#{Process.pid}"
    redis = Redis.new(url: ENV.fetch('REDIS_URL'))
    redis.scan_each(match: "#{namespace}:*") { |key| redis.del(key) }

    run_dummy_app(
      backend: 'redis',
      env: { 'REDIS_URL' => ENV.fetch('REDIS_URL'), 'KAAL_TEST_NAMESPACE' => namespace }
    ) do |app_root, _env, lines|
      expect(lines).to eq(['200', 'Kaal::Backend::RedisAdapter', 'true'])
      expect(redis.hget("#{namespace}:definitions", 'roda:heartbeat')).to include('"key":"roda:heartbeat"')
      expect(File.read(KaalRodaDummyAppSupport.job_log_path(app_root))).not_to be_empty
    end
  ensure
    if redis && namespace
      redis.scan_each(match: "#{namespace}:*") { |key| redis.del(key) }
      redis.close
    end
  end
end
