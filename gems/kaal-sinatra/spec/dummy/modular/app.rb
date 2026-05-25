# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

$LOAD_PATH.unshift(ENV.fetch('KAAL_SINATRA_LIB_PATH')) unless $LOAD_PATH.include?(ENV.fetch('KAAL_SINATRA_LIB_PATH'))

require 'sinatra/base'
require 'kaal/sinatra'

BACKEND_NAME = ENV.fetch('KAAL_TEST_BACKEND', 'memory')
BACKEND_URL = if BACKEND_NAME == 'redis'
                ENV.fetch('REDIS_URL')
              elsif %w[sqlite postgres mysql].include?(BACKEND_NAME)
                ENV.fetch('DATABASE_URL')
              end

class ExampleHeartbeatJob
  def self.perform(*)
    File.write(ENV.fetch('JOB_LOG_PATH'), "modular\n", mode: 'a')
  end
end

class ModularDummyApp < Sinatra::Base
  set :root, File.expand_path(__dir__)

  register Kaal::Sinatra::Extension

  File.write(
    File.expand_path('config/kaal.yml', root),
    <<~YAML
      defaults:
        backend: #{BACKEND_NAME}
        namespace: #{ENV.fetch('KAAL_TEST_NAMESPACE', 'kaal-sinatra-modular')}
        tick_interval: 5
        window_lookback: 120
        window_lookahead: 0
        lease_ttl: 125
        scheduler_config_path: config/kaal-scheduler.yml
        enable_log_dispatch_registry: #{%w[redis sqlite postgres mysql].include?(BACKEND_NAME)}
        enable_dispatch_recovery: false
        recovery_startup_jitter: 0
        delayed_job_allowed_class_prefixes: []
        backend_config:
    YAML
  )
  File.write(File.expand_path('config/kaal.yml', root), BACKEND_URL ? "          url: \"#{BACKEND_URL}\"\n" : "          {}\n", mode: 'a')

  kaal(
    namespace: ENV.fetch('KAAL_TEST_NAMESPACE', 'kaal-sinatra-modular'),
    start_scheduler: ENV.fetch('KAAL_START_SCHEDULER', '0') == '1'
  )

  get '/' do
    'modular'
  end
end
