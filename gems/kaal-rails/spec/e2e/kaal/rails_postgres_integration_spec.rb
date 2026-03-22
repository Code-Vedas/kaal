# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'

RSpec.describe Kaal::Rails, integration: :pg do
  include RailsIntegrationHelpers

  it 'auto-wires the backend and installs migrations through rake' do
    skip 'DATABASE_URL not set' if ENV['DATABASE_URL'].to_s.empty?

    KaalRailsDummyAppSupport.with_dummy_app do |app_root, env|
      pg_env = env.merge('DATABASE_URL' => ENV.fetch('DATABASE_URL'))
      KaalRailsDummyAppSupport.reset_database!(pg_env.fetch('DATABASE_URL'))
      KaalRailsDummyAppSupport.run!(app_root, pg_env, 'bin/rake', 'kaal:install:migrations')
      expect(KaalRailsDummyAppSupport.migration_slugs(app_root)).to eq(
        %w[create_kaal_definitions.rb create_kaal_dispatches.rb]
      )

      KaalRailsDummyAppSupport.run!(app_root, pg_env, 'bin/rails', 'db:migrate')
      output = runner_output(
        app_root,
        pg_env,
        [
          'class ExampleHeartbeatJob',
          '  def self.perform(*)',
          "    File.write(Rails.root.join('tmp/postgres.log'), \"postgres\\n\", mode: 'a')",
          '  end',
          'end',
          'class << Time',
          '  alias_method :kaal_original_now, :now',
          '  def now = utc(2026, 1, 1, 0, 0, 30)',
          'end',
          'Kaal.configure { |config| config.enable_log_dispatch_registry = true }',
          "Kaal.register(key: 'postgres:heartbeat', cron: '* * * * *', enqueue: ->(**) { ExampleHeartbeatJob.perform })",
          'Kaal.tick!',
          'puts Kaal.configuration.backend.class.name',
          'puts Kaal::ActiveRecord::DefinitionRecord.count',
          'puts Kaal::ActiveRecord::DispatchRecord.count',
          "puts [ActiveRecord::Base.connection.data_source_exists?('kaal_definitions'),",
          "      ActiveRecord::Base.connection.data_source_exists?('kaal_dispatches')].join(',')"
        ].join("\n")
      )
      lines = output.lines.map(&:strip)

      expect(lines[0]).to eq('Kaal::ActiveRecord::PostgresAdapter')
      expect(lines[1].to_i).to be >= 1
      expect(lines[2].to_i).to be >= 1
      expect(lines[3]).to eq('true,true')
      expect(File.read(File.join(app_root, 'tmp', 'postgres.log'))).to include('postgres')
    end
  end
end
