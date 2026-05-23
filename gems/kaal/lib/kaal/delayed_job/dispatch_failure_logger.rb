# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
module Kaal
  module DelayedJob
    # Shared delayed-dispatch failure logging for at-most-once dispatches.
    module DispatchFailureLogger
      module_function

      def log_claimed_dispatch_failure(logger:, job:, error:)
        return unless logger

        message = "Delayed job #{job.fetch(:job_id)} dispatch failed after claim; " \
                  "job_class=#{job.fetch(:job_class).inspect} " \
                  "queue=#{job[:queue].inspect} " \
                  "run_at=#{job.fetch(:run_at)} " \
                  'job was already claimed and will not be retried: ' \
                  "#{error.class}: #{error.message}"

        if logger.respond_to?(:fatal)
          logger.fatal(message)
        else
          logger.error(message)
        end
      end
    end
  end
end
