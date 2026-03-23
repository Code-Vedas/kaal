# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'kaal/roda'

class Roda
  # Roda plugin registry namespace.
  module RodaPlugins
    # Plugin that wires Kaal into Roda applications.
    module Kaal
      # Class-level DSL added by the plugin.
      module ClassMethods
        def kaal(**)
          ::Kaal::Roda.register!(self, **)
        end
      end
    end

    register_plugin(:kaal, Kaal)
  end
end
