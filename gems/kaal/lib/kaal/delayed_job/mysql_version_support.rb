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
        major, minor, patch = version_components(version_string)
        return 0 unless major && minor && patch

        (major * 10_000) + (minor * 100) + patch
      end

      def version_components(version_string)
        major, minor, patch = version_string.to_s.split('.', 3)
        [
          integer_prefix(major),
          integer_prefix(minor),
          integer_prefix(patch)
        ]
      end

      def integer_prefix(value)
        digits = value.to_s.each_char.take_while { |character| character.between?('0', '9') }.join
        return nil if digits.empty?

        digits.to_i
      end
    end
  end
end
