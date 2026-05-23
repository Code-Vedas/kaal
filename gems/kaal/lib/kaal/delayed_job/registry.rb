# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
module Kaal
  module DelayedJob
    # Raised when a delayed job with the same identifier already exists.
    class DuplicateJobError < StandardError; end

    # Base abstraction for delayed-job persistence.
    class Registry
      def enqueue(**)
        raise NotImplementedError, "#{self.class.name} must implement #enqueue"
      end

      def pop_due(**)
        raise NotImplementedError, "#{self.class.name} must implement #pop_due"
      end

      def find_job(_job_id)
        raise NotImplementedError, "#{self.class.name} must implement #find_job"
      end

      def all_jobs
        raise NotImplementedError, "#{self.class.name} must implement #all_jobs"
      end

      def claim_strategy
        raise NotImplementedError, "#{self.class.name} must implement #claim_strategy"
      end

      def requires_dispatch_lock?
        false
      end
    end
  end
end
