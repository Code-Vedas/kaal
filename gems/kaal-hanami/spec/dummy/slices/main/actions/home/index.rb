# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'hanami/action'

module Main
  module Actions
    module Home
      class Index < Hanami::Action
        def handle(_request, response)
          response.body = 'hanami'
        end
      end
    end
  end
end
