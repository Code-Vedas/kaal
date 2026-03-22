# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
module SinatraIntegrationHelpers
  def run_dummy_app(type, backend:, app_class_name:, env: {})
    KaalSinatraDummyAppSupport.with_dummy_app(type) do |app_root, default_env|
      merged_env = default_env.merge(env).merge('KAAL_TEST_BACKEND' => backend)

      if backend == 'sqlite'
        merged_env['DATABASE_URL'] = "sqlite://#{KaalSinatraDummyAppSupport.database_path(app_root)}"
        KaalSinatraDummyAppSupport.prepare_database!(backend, database_url: merged_env.fetch('DATABASE_URL'), app_root:)
      elsif %w[postgres mysql].include?(backend)
        KaalSinatraDummyAppSupport.prepare_database!(backend, database_url: merged_env.fetch('DATABASE_URL'), app_root:)
      end

      output = KaalSinatraDummyAppSupport.run!(app_root, merged_env, <<~RUBY)
        require 'rack/mock'
        require './app'

        class << Time
          alias_method :kaal_sinatra_original_now, :now

          def now
            utc(2026, 1, 1, 0, 0, 30)
          end
        end

        app = #{app_class_name}
        response = Rack::MockRequest.new(app).get('/')
        Kaal.tick!

        puts response.status
        puts Kaal.configuration.backend.class.name
        puts Kaal.registered?(key: 'sinatra:heartbeat')
      RUBY

      yield app_root, merged_env, output.lines.map(&:strip)
    end
  end
end
