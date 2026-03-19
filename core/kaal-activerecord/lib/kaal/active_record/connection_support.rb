# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
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
