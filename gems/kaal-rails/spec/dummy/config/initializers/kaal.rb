# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# rubocop:disable Rails/RootPathnameMethods
case ENV.fetch('KAAL_TEST_BACKEND', nil)
when 'memory'
  File.write(
    Rails.root.join('config/kaal.yml'),
    <<~YAML
      defaults:
        backend: memory
        namespace: kaal
        tick_interval: 5
        window_lookback: 120
        window_lookahead: 0
        lease_ttl: 125
        scheduler_config_path: config/kaal-scheduler.yml
        enable_dispatch_recovery: true
        enable_log_dispatch_registry: false
        delayed_job_allowed_class_prefixes: []
        backend_config: {}
    YAML
  )
when 'redis'
  namespace = ENV.fetch('KAAL_TEST_NAMESPACE', 'kaal-rails-test')
  redis_url = ENV.fetch('REDIS_URL')
  File.write(
    Rails.root.join('config/kaal.yml'),
    <<~YAML
      defaults:
        backend: redis
        namespace: #{namespace.dump}
        tick_interval: 5
        window_lookback: 120
        window_lookahead: 0
        lease_ttl: 125
        scheduler_config_path: config/kaal-scheduler.yml
        enable_dispatch_recovery: true
        enable_log_dispatch_registry: false
        delayed_job_allowed_class_prefixes: []
        backend_config:
          url: #{redis_url.dump}
    YAML
  )
end
# rubocop:enable Rails/RootPathnameMethods
