# frozen_string_literal: true

module Kaal
  module ActiveRecord
    # Active Record model for table-backed scheduler locks.
    class LockRecord < BaseRecord
      self.table_name = 'kaal_locks'
    end
  end
end
