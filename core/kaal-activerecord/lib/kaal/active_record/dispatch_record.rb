# frozen_string_literal: true

module Kaal
  module ActiveRecord
    # Active Record model for persisted dispatch audit entries.
    class DispatchRecord < BaseRecord
      self.table_name = 'kaal_dispatches'
    end
  end
end
