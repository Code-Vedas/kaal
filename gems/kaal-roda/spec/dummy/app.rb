# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

lib_path = ENV.fetch('KAAL_RODA_LIB_PATH', nil)
$LOAD_PATH.unshift(lib_path) if lib_path && !$LOAD_PATH.include?(lib_path)

require 'roda'
require 'sequel'
require 'kaal/roda'
require 'redis'

backend_name = ENV.fetch('KAAL_TEST_BACKEND', 'memory')

class ExampleHeartbeatJob
  def self.perform(*)
    File.write(ENV.fetch('JOB_LOG_PATH'), "roda\n", mode: 'a')
  end
end

Kaal.configure do |config|
  config.enable_log_dispatch_registry = %w[redis sqlite postgres mysql].include?(backend_name)
  config.enable_dispatch_recovery = false
  config.recovery_startup_jitter = 0
end

case backend_name
when 'memory'
  BACKEND_OPTIONS = { backend: Kaal::Backend::MemoryAdapter.new }.freeze
when 'redis'
  redis = Redis.new(url: ENV.fetch('REDIS_URL'))
  BACKEND_OPTIONS = { redis: redis }.freeze
when 'sqlite', 'postgres', 'mysql'
  database = Sequel.connect(ENV.fetch('DATABASE_URL'))
  BACKEND_OPTIONS = { database: database, adapter: backend_name }.freeze
else
  raise "Unsupported KAAL_TEST_BACKEND=#{backend_name.inspect}"
end

class RodaDummyApp < Roda
  opts[:root] = File.expand_path(__dir__)
  opts[:environment] = ENV.fetch('RACK_ENV', 'development')

  plugin :kaal

  kaal(
    **BACKEND_OPTIONS,
    namespace: ENV.fetch('KAAL_TEST_NAMESPACE', 'kaal-roda'),
    start_scheduler: ENV.fetch('KAAL_START_SCHEDULER', '0') == '1'
  )

  route do |r|
    r.root { 'roda' }
  end
end
