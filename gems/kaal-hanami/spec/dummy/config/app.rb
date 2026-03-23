# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
lib_path = ENV.fetch('KAAL_HANAMI_LIB_PATH', nil)
$LOAD_PATH.unshift(lib_path) if lib_path && !$LOAD_PATH.include?(lib_path)

require 'hanami'
require 'kaal/hanami'
require 'redis'
require 'sequel'
require 'stringio'

BACKEND_NAME = ENV.fetch('KAAL_TEST_BACKEND', 'memory')

class ExampleHeartbeatJob
  def self.perform(*)
    File.write(ENV.fetch('JOB_LOG_PATH'), "hanami\n", mode: 'a')
  end
end

case BACKEND_NAME
when 'memory'
  BACKEND_OPTIONS = { backend: Kaal::Backend::MemoryAdapter.new }.freeze
when 'redis'
  redis = Redis.new(url: ENV.fetch('REDIS_URL'))
  BACKEND_OPTIONS = { redis: redis }.freeze
when 'sqlite', 'postgres', 'mysql'
  database = Sequel.connect(ENV.fetch('DATABASE_URL'))
  BACKEND_OPTIONS = { database: database, adapter: BACKEND_NAME }.freeze
else
  raise "Unsupported KAAL_TEST_BACKEND=#{BACKEND_NAME.inspect}"
end

module TestApp
  class App < Hanami::App
    config.logger.stream = StringIO.new

    Kaal.configure do |config|
      config.enable_log_dispatch_registry = %w[redis sqlite postgres mysql].include?(BACKEND_NAME)
      config.enable_dispatch_recovery = false
      config.recovery_startup_jitter = 0
    end

    Kaal::Hanami.configure!(
      self,
      **BACKEND_OPTIONS,
      namespace: ENV.fetch('KAAL_TEST_NAMESPACE', 'kaal-hanami'),
      start_scheduler: ENV.fetch('KAAL_START_SCHEDULER', '0') == '1'
    )
  end
end
