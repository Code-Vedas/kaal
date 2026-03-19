# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
module Kaal
  module ActiveRecord
    # Active Record model for table-backed scheduler locks.
    class LockRecord < BaseRecord
      self.table_name = 'kaal_locks'
    end
  end
end
