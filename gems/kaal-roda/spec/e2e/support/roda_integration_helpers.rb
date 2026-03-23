# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
module RodaIntegrationHelpers
  def run_dummy_app(backend:, env: {})
    KaalRodaDummyAppSupport.with_dummy_app do |app_root, default_env|
      merged_env = default_env.merge(env).merge('KAAL_TEST_BACKEND' => backend)

      if backend == 'sqlite'
        merged_env['DATABASE_URL'] = "sqlite://#{KaalRodaDummyAppSupport.database_path(app_root)}"
        KaalRodaDummyAppSupport.prepare_database!(backend, database_url: merged_env.fetch('DATABASE_URL'), app_root:)
      elsif %w[postgres mysql].include?(backend)
        KaalRodaDummyAppSupport.prepare_database!(backend, database_url: merged_env.fetch('DATABASE_URL'), app_root:)
      end

      output = KaalRodaDummyAppSupport.run!(app_root, merged_env, <<~RUBY)
        require 'rack/mock'
        require './app'

        class << Time
          alias_method :kaal_roda_original_now, :now

          def now
            utc(2026, 1, 1, 0, 0, 30)
          end
        end

        response = Rack::MockRequest.new(RodaDummyApp.app).get('/')
        Kaal.tick!

        puts response.status
        puts Kaal.configuration.backend.class.name
        puts Kaal.registered?(key: 'roda:heartbeat')
      RUBY

      yield app_root, merged_env, output.lines.map(&:strip)
    end
  end
end
