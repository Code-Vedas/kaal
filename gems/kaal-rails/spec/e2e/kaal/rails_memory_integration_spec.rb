# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'

RSpec.describe Kaal::Rails, integration: :memory do
  include RailsIntegrationHelpers

  it 'boots the dummy app with a memory backend override and executes a scheduled job' do
    KaalRailsDummyAppSupport.with_dummy_app do |app_root, env|
      File.write(
        File.join(app_root, 'config', 'kaal.yml'),
        <<~YAML
          defaults:
            backend: memory
            namespace: kaal
            tick_interval: 5
            window_lookback: 120
            window_lookahead: 0
            lease_ttl: 125
            scheduler_config_path: config/kaal-scheduler.yml
            enable_dispatch_recovery: true
            enable_log_dispatch_registry: false
            delayed_job_allowed_class_prefixes: []
            backend_config: {}
        YAML
      )
      File.write(
        File.join(app_root, 'config', 'kaal-scheduler.yml'),
        <<~YAML
          defaults:
            jobs:
              - key: "example:heartbeat"
                cron: "* * * * *"
                job_class: "ExampleHeartbeatJob"
                enabled: true
        YAML
      )

      output = runner_output(
        app_root,
        env,
        <<~RUBY
          class ExampleHeartbeatJob
            def self.perform(*)
              File.write(Rails.root.join('tmp/memory.log'), "memory\\n", mode: 'a')
            end
          end

          Kaal.load_scheduler_file!
          Kaal.tick!
          puts Kaal.configuration.backend.class.name
        RUBY
      )

      expect(output.strip).to eq('Kaal::Backend::MemoryAdapter')
      expect(File.read(File.join(app_root, 'tmp', 'memory.log'))).to include('memory')
    end
  end
end
