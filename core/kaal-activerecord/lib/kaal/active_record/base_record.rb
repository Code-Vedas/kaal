# frozen_string_literal: true

module Kaal
  module ActiveRecord
    # Shared abstract Active Record base class for Kaal tables.
    class BaseRecord < ::ActiveRecord::Base
      self.abstract_class = true
    end
  end
end
