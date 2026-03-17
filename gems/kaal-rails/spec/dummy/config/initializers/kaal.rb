# frozen_string_literal: true

case ENV.fetch('KAAL_TEST_BACKEND', nil)
when 'memory'
  Kaal.configure do |config|
    config.backend = Kaal::Backend::MemoryAdapter.new
    config.scheduler_config_path = 'config/scheduler.yml'
  end
when 'redis'
  require 'redis'

  Kaal.configure do |config|
    config.backend = Kaal::Backend::RedisAdapter.new(Redis.new(url: ENV.fetch('REDIS_URL')), namespace: 'kaal-rails-test')
    config.scheduler_config_path = 'config/scheduler.yml'
  end
end
