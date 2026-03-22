# frozen_string_literal: true

$LOAD_PATH.unshift(ENV.fetch('KAAL_SINATRA_LIB_PATH')) unless $LOAD_PATH.include?(ENV.fetch('KAAL_SINATRA_LIB_PATH'))

require 'sinatra'
require 'sequel'
require 'kaal/sinatra'
require 'redis'

backend_name = ENV.fetch('KAAL_TEST_BACKEND', 'memory')

class ExampleHeartbeatJob
  def self.perform(*)
    File.write(ENV.fetch('JOB_LOG_PATH'), "classic\n", mode: 'a')
  end
end

set :root, File.expand_path(__dir__)

register Kaal::Sinatra::Extension

Kaal.configure do |config|
  config.enable_log_dispatch_registry = %w[redis sqlite postgres mysql].include?(backend_name)
  config.enable_dispatch_recovery = false
  config.recovery_startup_jitter = 0
end

case backend_name
when 'memory'
  backend_options = { backend: Kaal::Backend::MemoryAdapter.new }
when 'redis'
  redis = Redis.new(url: ENV.fetch('REDIS_URL'))
  backend_options = { redis: redis }
when 'sqlite', 'postgres', 'mysql'
  database = Sequel.connect(ENV.fetch('DATABASE_URL'))
  backend_options = { database: database, adapter: backend_name }
else
  raise "Unsupported KAAL_TEST_BACKEND=#{backend_name.inspect}"
end

Kaal::Sinatra.register!(
  settings,
  **backend_options,
  namespace: ENV.fetch('KAAL_TEST_NAMESPACE', 'kaal-sinatra-classic'),
  start_scheduler: ENV.fetch('KAAL_START_SCHEDULER', '0') == '1'
)

get '/' do
  'classic'
end
