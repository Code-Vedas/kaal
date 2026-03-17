# frozen_string_literal: true

module Kaal
  module ActiveRecord
    # Active Record model for persisted scheduler definitions.
    class DefinitionRecord < BaseRecord
      self.table_name = 'kaal_definitions'
    end
  end
end
