# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
module HanamiIntegrationHelpers
  def run_dummy_app(backend:, env: {})
    KaalHanamiDummyAppSupport.with_dummy_app do |app_root, default_env|
      merged_env = default_env.merge(env).merge('KAAL_TEST_BACKEND' => backend)

      if backend == 'sqlite'
        merged_env['DATABASE_URL'] = "sqlite://#{KaalHanamiDummyAppSupport.database_path(app_root)}"
        KaalHanamiDummyAppSupport.prepare_database!(backend, database_url: merged_env.fetch('DATABASE_URL'), app_root:)
      elsif %w[postgres mysql].include?(backend)
        KaalHanamiDummyAppSupport.prepare_database!(backend, database_url: merged_env.fetch('DATABASE_URL'), app_root:)
      end

      output = KaalHanamiDummyAppSupport.run!(app_root, merged_env, <<~RUBY)
        require 'rack/mock'
        require 'hanami/boot'

        class << Time
          alias_method :kaal_hanami_original_now, :now

          def now
            utc(2026, 1, 1, 0, 0, 30)
          end
        end

        response = Rack::MockRequest.new(Hanami.app).get('/')
        Kaal.tick!

        puts response.status
        puts Kaal.configuration.backend.class.name
        puts Kaal.registered?(key: 'hanami:heartbeat')
      RUBY

      yield app_root, merged_env, output.lines.map(&:strip)
    end
  end
end
