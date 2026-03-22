# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'

RSpec.describe Kaal::Rails, integration: :sqlite do
  include RailsIntegrationHelpers

  it 'auto-wires the backend, exposes tasks, generates files, and migrates' do
    KaalRailsDummyAppSupport.with_dummy_app do |app_root, env|
      task_output = KaalRailsDummyAppSupport.run!(app_root, env, 'bin/rake', '-T', 'kaal')
      expect(task_output).to include('kaal:install:all', 'kaal:install:migrations')

      KaalRailsDummyAppSupport.run!(app_root, env, 'bin/rails', 'generate', 'kaal:install', '--backend=sqlite')
      expect(File).to exist(File.join(app_root, 'config', 'scheduler.yml'))
      expect(KaalRailsDummyAppSupport.migration_slugs(app_root)).to eq(
        %w[create_kaal_definitions.rb create_kaal_dispatches.rb create_kaal_locks.rb]
      )

      KaalRailsDummyAppSupport.run!(app_root, env, 'bin/rails', 'db:migrate')
      output = runner_output(
        app_root,
        env,
        [
          'class ExampleHeartbeatJob',
          '  def self.perform(*)',
          "    File.write(Rails.root.join('tmp/sqlite.log'), \"sqlite\\n\", mode: 'a')",
          '  end',
          'end',
          'class << Time',
          '  alias_method :kaal_original_now, :now',
          '  def now = utc(2026, 1, 1, 0, 0, 30)',
          'end',
          'Kaal.configure { |config| config.enable_log_dispatch_registry = true }',
          "Kaal.register(key: 'sqlite:heartbeat', cron: '* * * * *', enqueue: ->(**) { ExampleHeartbeatJob.perform })",
          'Kaal.tick!',
          'puts Kaal.configuration.backend.class.name',
          'puts Kaal::ActiveRecord::DefinitionRecord.count',
          'puts Kaal::ActiveRecord::DispatchRecord.count',
          'puts Kaal::ActiveRecord::LockRecord.count',
          "puts [ActiveRecord::Base.connection.data_source_exists?('kaal_definitions'),",
          "      ActiveRecord::Base.connection.data_source_exists?('kaal_dispatches'),",
          "      ActiveRecord::Base.connection.data_source_exists?('kaal_locks')].join(',')"
        ].join("\n")
      )
      lines = output.lines.map(&:strip)

      expect(lines[0]).to eq('Kaal::ActiveRecord::DatabaseAdapter')
      expect(lines[1].to_i).to be >= 1
      expect(lines[2].to_i).to be >= 1
      expect(lines[3].to_i).to be >= 1
      expect(lines[4]).to eq('true,true,true')
      expect(File.read(File.join(app_root, 'tmp', 'sqlite.log'))).to include('sqlite')
    end
  end
end
