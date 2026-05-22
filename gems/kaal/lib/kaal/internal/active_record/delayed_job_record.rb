# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
module Kaal
  module Internal
    module ActiveRecord
      # Active Record model for persisted delayed jobs.
      class DelayedJobRecord < BaseRecord
        self.table_name = 'kaal_delayed_jobs'
      end
    end
  end
end
