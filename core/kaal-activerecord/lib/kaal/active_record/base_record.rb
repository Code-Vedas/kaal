# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
module Kaal
  module ActiveRecord
    # Shared abstract ApplicationRecord class for Kaal tables.
    class ApplicationRecord < ::ActiveRecord::Base
      self.abstract_class = true
    end

    # Shared abstract Active Record base class for Kaal tables.
    class BaseRecord < ApplicationRecord
      self.abstract_class = true
    end
  end
end
