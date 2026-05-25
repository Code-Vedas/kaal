# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'
require 'redis'

RSpec.describe Kaal::Rails, integration: :redis do
  include RailsIntegrationHelpers

  it 'boots the dummy app with a redis backend override and loads scheduler definitions into redis' do
    skip 'REDIS_URL not set' if ENV['REDIS_URL'].to_s.empty?

    namespace = nil
    redis = nil

    KaalRailsDummyAppSupport.with_dummy_app do |app_root, env|
      namespace = "kaal-rails-test:#{File.basename(app_root)}"
      redis = Redis.new(url: ENV.fetch('REDIS_URL'))
      redis.scan_each(match: "#{namespace}:*") { |key| redis.del(key) }
      File.write(
        File.join(app_root, 'config', 'kaal.yml'),
        <<~YAML
          defaults:
            backend: redis
            namespace: #{namespace}
            tick_interval: 5
            window_lookback: 120
            window_lookahead: 0
            lease_ttl: 125
            scheduler_config_path: config/kaal-scheduler.yml
            enable_dispatch_recovery: true
            enable_log_dispatch_registry: false
            delayed_job_allowed_class_prefixes: []
            backend_config:
              url: "#{ENV.fetch('REDIS_URL')}"
        YAML
      )

      File.write(
        File.join(app_root, 'config', 'kaal-scheduler.yml'),
        <<~YAML
          defaults:
            jobs:
              - key: "example:heartbeat"
                cron: "* * * * *"
                job_class: "ExampleHeartbeatJob"
                enabled: true
        YAML
      )

      output = runner_output(
        app_root,
        env.merge(
          'KAAL_TEST_NAMESPACE' => namespace,
          'REDIS_URL' => ENV.fetch('REDIS_URL')
        ),
        <<~RUBY
          class ExampleHeartbeatJob
            def self.perform(*) = nil
          end

          Kaal.load_scheduler_file!
          Kaal.tick!
          puts Kaal.configuration.backend.class.name
        RUBY
      )
      expect(output.strip).to eq('Kaal::Backend::RedisAdapter')
      expect(redis.hget("#{namespace}:definitions", 'example:heartbeat')).to include('"key":"example:heartbeat"')
    ensure
      if redis && namespace
        redis.scan_each(match: "#{namespace}:*") { |key| redis.del(key) }
        redis.close
      end
    end
  end
end
