# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
case ENV.fetch('KAAL_TEST_BACKEND', nil)
when 'memory'
  Kaal.configure do |config|
    config.backend = Kaal::Backend::MemoryAdapter.new
    config.scheduler_config_path = 'config/scheduler.yml'
  end
when 'redis'
  require 'redis'
  namespace = ENV.fetch('KAAL_TEST_NAMESPACE', 'kaal-rails-test')

  Kaal.configure do |config|
    config.backend = Kaal::Backend::RedisAdapter.new(
      Redis.new(url: ENV.fetch('REDIS_URL')),
      namespace: namespace
    )
    config.namespace = namespace
    config.scheduler_config_path = 'config/scheduler.yml'
  end
end
