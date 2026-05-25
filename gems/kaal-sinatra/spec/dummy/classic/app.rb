# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

$LOAD_PATH.unshift(ENV.fetch('KAAL_SINATRA_LIB_PATH')) unless $LOAD_PATH.include?(ENV.fetch('KAAL_SINATRA_LIB_PATH'))

require 'sinatra'
require 'kaal/sinatra'

backend_name = ENV.fetch('KAAL_TEST_BACKEND', 'memory')
backend_url = if backend_name == 'redis'
                ENV.fetch('REDIS_URL')
              elsif %w[sqlite postgres mysql].include?(backend_name)
                ENV.fetch('DATABASE_URL')
              end

class ExampleHeartbeatJob
  def self.perform(*)
    File.write(ENV.fetch('JOB_LOG_PATH'), "classic\n", mode: 'a')
  end
end

set :root, File.expand_path(__dir__)

register Kaal::Sinatra::Extension

File.write(
  File.expand_path('config/kaal.yml', settings.root),
  <<~YAML
    defaults:
      backend: #{backend_name}
      namespace: #{ENV.fetch('KAAL_TEST_NAMESPACE', 'kaal-sinatra-classic')}
      tick_interval: 5
      window_lookback: 120
      window_lookahead: 0
      lease_ttl: 125
      scheduler_config_path: config/kaal-scheduler.yml
      enable_log_dispatch_registry: #{%w[redis sqlite postgres mysql].include?(backend_name)}
      enable_dispatch_recovery: false
      recovery_startup_jitter: 0
      delayed_job_allowed_class_prefixes: []
      backend_config:
  YAML
)
File.write(File.expand_path('config/kaal.yml', settings.root), backend_url ? "        url: \"#{backend_url}\"\n" : "        {}\n", mode: 'a')

Kaal::Sinatra.register!(
  settings,
  namespace: ENV.fetch('KAAL_TEST_NAMESPACE', 'kaal-sinatra-classic'),
  start_scheduler: ENV.fetch('KAAL_START_SCHEDULER', '0') == '1'
)

get '/' do
  'classic'
end
