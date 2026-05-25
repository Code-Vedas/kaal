# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'

RSpec.describe Kaal::CLI, integration: :memory do
  it 'supports init, status, tick, explain, and next against a real project' do
    KaalIntegrationSupport.with_project_root('cli-memory') do |root|
      init_output = KaalCliIntegrationSupport.run!('init', '--backend=memory', '--root', root)
      expect(init_output).to include('Initialized Kaal project for memory backend')
      expect(File).to exist(File.join(root, 'config', 'kaal.yml'))
      expect(File).to exist(File.join(root, 'config', 'kaal-scheduler.yml'))
      FileUtils.mkdir_p(File.join(root, 'tmp'))
      FileUtils.mkdir_p(File.join(root, 'lib'))

      File.write(
        File.join(root, 'lib', 'example_heartbeat_job.rb'),
        <<~RUBY
          class ExampleHeartbeatJob
            def self.perform(*)
              File.write(File.expand_path('../tmp/heartbeat.log', __dir__), "tick\\n", mode: 'a')
            end
          end
        RUBY
      )

      File.write(
        File.join(root, 'config', 'kaal.yml'),
        <<~YAML
          <% require #{File.join(root, 'lib', 'example_heartbeat_job.rb').inspect} %>
          defaults:
            backend: memory
            namespace: kaal
            tick_interval: 1
            window_lookback: 3600
            window_lookahead: 0
            lease_ttl: 3605
            scheduler_config_path: config/kaal-scheduler.yml
            enable_dispatch_recovery: true
            enable_log_dispatch_registry: false
            delayed_job_allowed_class_prefixes: []
            backend_config: {}
        YAML
      )
      File.write(
        File.join(root, 'config', 'kaal-scheduler.yml'),
        <<~YAML
          defaults:
            jobs:
              - key: "example:heartbeat"
                cron: "* * * * *"
                job_class: "ExampleHeartbeatJob"
                enabled: true
        YAML
      )

      status_output = KaalCliIntegrationSupport.run!('status', '--root', root)
      expect(status_output).to include('Kaal v0.5.0', 'Registered jobs: 1', 'example:heartbeat')

      tick_output = KaalCliIntegrationSupport.run!('tick', '--root', root)
      expect(tick_output).to include('Kaal tick completed')
      expect(File.read(File.join(root, 'tmp', 'heartbeat.log'))).to include('tick')

      explain_output = KaalCliIntegrationSupport.run!('explain', '*/15 * * * *')
      expect(explain_output.strip).not_to be_empty

      next_output = KaalCliIntegrationSupport.run!('next', '0 9 * * 1', '--count', '3')
      next_lines = next_output.lines.map(&:strip).reject(&:empty?)
      expect(next_lines.length).to eq(3)
      next_lines.each { |line| expect { Time.iso8601(line) }.not_to raise_error }
    end
  end

  it 'supports start for a real project in the foreground' do
    KaalIntegrationSupport.with_project_root('cli-start') do |root|
      FileUtils.mkdir_p(File.join(root, 'config'))
      FileUtils.mkdir_p(File.join(root, 'tmp'))
      FileUtils.mkdir_p(File.join(root, 'lib'))
      File.write(
        File.join(root, 'lib', 'example_heartbeat_job.rb'),
        <<~RUBY
          class ExampleHeartbeatJob
            def self.perform(*)
              File.write(File.expand_path('../tmp/start.log', __dir__), "started\\n", mode: 'a')
            end
          end
        RUBY
      )
      KaalIntegrationSupport.write_config(
        root,
        <<~YAML
          <% require #{File.join(root, 'lib', 'example_heartbeat_job.rb').inspect} %>
          defaults:
            backend: memory
            namespace: kaal
            tick_interval: 1
            window_lookback: 3600
            window_lookahead: 0
            lease_ttl: 3605
            scheduler_config_path: config/kaal-scheduler.yml
            enable_dispatch_recovery: true
            enable_log_dispatch_registry: false
            delayed_job_allowed_class_prefixes: []
            backend_config: {}
        YAML
      )
      File.write(
        File.join(root, 'config', 'kaal-scheduler.yml'),
        <<~YAML
          defaults:
            jobs:
              - key: "cli:start"
                cron: "* * * * *"
                job_class: "ExampleHeartbeatJob"
                enabled: true
        YAML
      )

      output, wait_thread = KaalCliIntegrationSupport.start!('start', '--root', root)
      started_output = KaalCliIntegrationSupport.wait_for_output(output, /Kaal scheduler started in foreground/)
      Timeout.timeout(10) do
        sleep 0.1 until File.exist?(File.join(root, 'tmp', 'start.log'))
      end

      Process.kill('TERM', wait_thread.pid)
      final_output = started_output
      final_output << output.read.to_s
      expect(final_output).to include('Kaal scheduler started in foreground', 'Received TERM, stopping Kaal scheduler...')
      expect(File.read(File.join(root, 'tmp', 'start.log'))).to include('started')
    ensure
      output&.close
    end
  end
end
