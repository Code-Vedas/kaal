# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

lib_path = ENV.fetch('KAAL_RODA_LIB_PATH', nil)
$LOAD_PATH.unshift(lib_path) if lib_path && !$LOAD_PATH.include?(lib_path)

require 'roda'
require 'kaal/roda'

backend_name = ENV.fetch('KAAL_TEST_BACKEND', 'memory')
backend_url = if backend_name == 'redis'
                ENV.fetch('REDIS_URL')
              elsif %w[sqlite postgres mysql].include?(backend_name)
                ENV.fetch('DATABASE_URL')
              end

class ExampleHeartbeatJob
  def self.perform(*)
    File.write(ENV.fetch('JOB_LOG_PATH'), "roda\n", mode: 'a')
  end
end

File.write(
  File.expand_path('config/kaal.yml', __dir__),
  <<~YAML
    defaults:
      backend: #{backend_name}
      namespace: #{ENV.fetch('KAAL_TEST_NAMESPACE', 'kaal-roda')}
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
File.write(File.expand_path('config/kaal.yml', __dir__), backend_url ? "        url: \"#{backend_url}\"\n" : "        {}\n", mode: 'a')

class RodaDummyApp < Roda
  opts[:root] = File.expand_path(__dir__)
  opts[:environment] = ENV.fetch('RACK_ENV', 'development')

  plugin :kaal

  kaal(
    namespace: ENV.fetch('KAAL_TEST_NAMESPACE', 'kaal-roda'),
    start_scheduler: ENV.fetch('KAAL_START_SCHEDULER', '0') == '1'
  )

  route do |r|
    r.root { 'roda' }
  end
end
