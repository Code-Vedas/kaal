# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'tzinfo'

module Kaal
  # Resolves the configured scheduler time zone, preferring explicit config.
  class SchedulerTimeZoneResolver
    DEFAULT_TIME_ZONE = 'UTC'

    def initialize(configuration:)
      @configuration = configuration
    end

    def time_zone_identifier
      zone = begin
        Time.zone
      rescue NoMethodError
        nil
      end
      configured_time_zone || zone&.tzinfo&.identifier || DEFAULT_TIME_ZONE
    end

    private

    def configured_time_zone
      value = normalized_time_zone_value
      return nil if value.empty?

      TZInfo::Timezone.get(value)
      value
    rescue TZInfo::InvalidTimezoneIdentifier
      raise ConfigurationError, "Invalid time_zone configuration: #{raw_time_zone_value.inspect} (normalized: #{value.inspect})"
    end

    def normalized_time_zone_value
      value = raw_time_zone_value
      return DEFAULT_TIME_ZONE if value.casecmp?(DEFAULT_TIME_ZONE)

      value
    end

    def raw_time_zone_value
      @configuration.time_zone.to_s.strip
    end
  end
end
