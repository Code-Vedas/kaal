# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
module Kaal
  # Loads scheduler.yml at framework boot time while respecting missing-file policy.
  class SchedulerBootLoader
    def initialize(configuration_provider:, logger:, runtime_context:, load_scheduler_file:)
      @configuration_provider = configuration_provider
      @logger = logger
      @runtime_context = runtime_context
      @load_scheduler_file = load_scheduler_file
    end

    def load_on_boot
      load_on_boot!
    end

    def load_on_boot!
      configuration = fetch_configuration
      return unless configuration

      return load_scheduler_file if configuration.scheduler_missing_file_policy == :error

      scheduler_path = configuration.scheduler_config_path.to_s.strip
      return if scheduler_path.empty?

      absolute_path = @runtime_context.resolve_path(scheduler_path)
      unless File.exist?(absolute_path)
        @logger&.warn("Scheduler file not found at #{absolute_path}")
        return
      end

      load_scheduler_file
    end

    private

    def load_scheduler_file
      @load_scheduler_file.call
    end

    def fetch_configuration
      @configuration_provider.call
    rescue NameError => e
      @logger&.debug("Skipping scheduler file boot load due to configuration error: #{e.message}")
      nil
    end
  end
end
