# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Kaal
  # Shared deep hash key transformation helpers for scheduler payloads.
  module SchedulerHashTransform
    private

    def stringify_keys(object)
      Kaal::Support::HashTools.stringify_keys(object)
    end

    def symbolize_keys_deep(object)
      Kaal::Support::HashTools.symbolize_keys(object)
    end
  end
end
