# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
module Kaal
  module Hanami
    # Rack middleware that bootstraps Kaal for Hanami applications.
    class Middleware
      def initialize(
        app,
        hanami_app:,
        backend: nil,
        database: nil,
        redis: nil,
        scheduler_config_path: 'config/scheduler.yml',
        namespace: nil,
        start_scheduler: false,
        adapter: nil,
        root: nil,
        environment: nil
      )
        @app = app

        Kaal::Hanami.register!(
          hanami_app,
          backend:,
          database:,
          redis:,
          scheduler_config_path:,
          namespace:,
          start_scheduler:,
          adapter:,
          root:,
          environment:
        )
      end

      def call(env)
        @app.call(env)
      end
    end
  end
end
