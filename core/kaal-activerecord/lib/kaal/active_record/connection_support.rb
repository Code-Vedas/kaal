# frozen_string_literal: true

module Kaal
  module ActiveRecord
    # Establishes and reuses the Active Record connection for adapter models.
    module ConnectionSupport
      module_function

      def configure!(connection = nil)
        return BaseRecord unless connection

        BaseRecord.establish_connection(connection)
        BaseRecord
      end
    end
  end
end
