# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
module Kaal
  module Config
    # Evaluates whether delayed-job class resolution is too open for the
    # current deployment shape and returns the matching warning message.
    module DelayedJobSecurityPolicy
      WARNING_MESSAGE = 'Delayed jobs resolve stored job_class values at dispatch time. ' \
                        'delayed_job_allowed_class_prefixes is empty, so class resolution is unrestricted on this shared backend. ' \
                        'Configure a restrictive delayed_job_allowed_class_prefixes list for production deployments.'

      module_function

      def warning_for(configuration)
        return unless production_like_environment?
        return unless shared_delayed_job_backend?(configuration.backend)
        return unless Array(configuration.delayed_job_allowed_class_prefixes).empty?

        WARNING_MESSAGE
      end

      def production_like_environment?(env: ENV, rails: current_rails)
        rails_env = rails_environment(rails)
        return rails_env.production? if rails_env

        %w[RACK_ENV HANAMI_ENV APP_ENV RAILS_ENV RUBY_ENV].any? do |key|
          env.fetch(key, nil).to_s.strip == 'production'
        end
      rescue StandardError
        false
      end

      def shared_delayed_job_backend?(backend)
        !!backend.delayed_store && !backend.is_a?(Kaal::Backend::MemoryAdapter)
      rescue NoMethodError
        false
      end

      def current_rails
        return unless defined?(::Rails)

        ::Rails
      end

      def rails_environment(rails)
        rails.env
      rescue StandardError
        nil
      end
    end
  end
end
