# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

$LOAD_PATH.unshift(ENV.fetch('KAAL_SINATRA_LIB_PATH')) unless $LOAD_PATH.include?(ENV.fetch('KAAL_SINATRA_LIB_PATH'))

require 'sinatra/base'
require 'sequel'
require 'kaal/sinatra'
require 'redis'

backend_name = ENV.fetch('KAAL_TEST_BACKEND', 'memory')

class ExampleHeartbeatJob
  def self.perform(*)
    File.write(ENV.fetch('JOB_LOG_PATH'), "modular\n", mode: 'a')
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

class ModularDummyApp < Sinatra::Base
  set :root, File.expand_path(__dir__)

  register Kaal::Sinatra::Extension

  kaal(
    **BACKEND_OPTIONS,
    namespace: ENV.fetch('KAAL_TEST_NAMESPACE', 'kaal-sinatra-modular'),
    start_scheduler: ENV.fetch('KAAL_START_SCHEDULER', '0') == '1'
  )

  get '/' do
    'modular'
  end
end
