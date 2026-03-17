# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'active_support/time'

module Kaal
  # Resolves the scheduler time zone without mutating global time-zone state.
  class SchedulerTimeZoneResolver
    DEFAULT_TIME_ZONE_PROVIDER = lambda do
      Time.respond_to?(:zone) ? Time.zone : nil
    end

    def initialize(configuration:, time_zone_provider: DEFAULT_TIME_ZONE_PROVIDER)
      @configuration = configuration
      @time_zone_provider = time_zone_provider
    end

    def time_zone
      configured_time_zone || rails_time_zone || ActiveSupport::TimeZone['UTC']
    end

    def time_zone_identifier
      time_zone.tzinfo.name
    end

    private

    def configured_time_zone
      configured_value = @configuration.time_zone.to_s.strip
      return nil if configured_value.empty?

      ActiveSupport::TimeZone[configured_value] || raise(
        ConfigurationError,
        "Invalid time_zone configuration: #{configured_value.inspect}"
      )
    end

    def rails_time_zone
      zone = @time_zone_provider.call
      return nil unless zone

      resolved_zone = ActiveSupport::TimeZone[zone] || zone
      return resolved_zone if resolved_zone.respond_to?(:tzinfo)

      nil
    rescue StandardError
      nil
    end
  end
end
