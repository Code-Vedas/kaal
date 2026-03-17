# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'kaal/config/configuration'
require 'kaal/config/scheduler_config_error'
require 'kaal/config/scheduler_time_zone_resolver'

module Kaal
  # Configuration-related types and validation helpers.
  module Config
    Configuration = ::Kaal::Configuration
    ConfigurationError = ::Kaal::ConfigurationError
    SchedulerConfigError = ::Kaal::SchedulerConfigError
    SchedulerTimeZoneResolver = ::Kaal::SchedulerTimeZoneResolver
  end
end
