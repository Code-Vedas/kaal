# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'tzinfo'

module Kaal
  # Resolves the configured scheduler time zone without framework fallbacks.
  class SchedulerTimeZoneResolver
    DEFAULT_TIME_ZONE = 'UTC'

    def initialize(configuration:)
      @configuration = configuration
    end

    def time_zone_identifier
      configured_time_zone || DEFAULT_TIME_ZONE
    end

    private

    def configured_time_zone
      value = @configuration.time_zone.to_s.strip
      return nil if value.empty?

      TZInfo::Timezone.get(value)
      value
    rescue TZInfo::InvalidTimezoneIdentifier
      raise ConfigurationError, "Invalid time_zone configuration: #{value.inspect}"
    end
  end
end
