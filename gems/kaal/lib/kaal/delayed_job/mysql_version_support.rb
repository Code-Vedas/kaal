# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
module Kaal
  module DelayedJob
    # MySQL version helper for delayed-job claim strategy selection.
    module MySQLVersionSupport
      MINIMUM_SKIP_LOCKED_VERSION = 800_00

      module_function

      def skip_locked_supported?(version_string)
        version_number(version_string) >= MINIMUM_SKIP_LOCKED_VERSION
      end

      def version_number(version_string)
        match = version_string.to_s.match(/(\d+)\.(\d+)\.(\d+)/)
        return 0 unless match

        major, minor, patch = match.captures.map(&:to_i)
        (major * 10_000) + (minor * 100) + patch
      end
    end
  end
end
