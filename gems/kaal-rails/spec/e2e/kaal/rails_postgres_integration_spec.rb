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
          'puts Kaal.configuration.backend.class.name',
          "puts [ActiveRecord::Base.connection.data_source_exists?('kaal_definitions'),",
          "      ActiveRecord::Base.connection.data_source_exists?('kaal_dispatches')].join(',')"
        ].join("\n")
      )
      lines = output.lines.map(&:strip)

      expect(lines[0]).to eq('Kaal::ActiveRecord::PostgresAdapter')
      expect(lines[1]).to eq('true,true')
    end
  end
end

