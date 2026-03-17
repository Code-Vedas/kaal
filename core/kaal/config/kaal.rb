# frozen_string_literal: true

require 'kaal'

Kaal.configure do |config|
  config.backend = Kaal::Backend::MemoryAdapter.new
  config.tick_interval = 5
  config.window_lookback = 120
  config.lease_ttl = 125
  config.scheduler_config_path = 'config/scheduler.yml'
end
