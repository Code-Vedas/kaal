# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Kaal
  # Finds all absolute fire times for a parsed cron expression within a window.
  class OccurrenceFinder
    def initialize(configuration:)
      @configuration = configuration
    end

    def call(cron:, start_time:, end_time:)
      occurrences = []
      current_time = start_time.getutc
      normalized_end_time = end_time.getutc
      normalized_end_time_unix = normalized_end_time.to_f

      while current_time <= normalized_end_time
        next_occurrence = cron.next_time(current_time)
        break unless next_occurrence

        next_occurrence_unix = next_occurrence.to_f
        break if next_occurrence_unix > normalized_end_time_unix

        fire_time = Time.at(next_occurrence_unix).utc
        occurrences << fire_time
        current_time = Time.at(next_occurrence_unix + 1).utc
      end

      occurrences
    rescue StandardError => e
      @configuration.logger&.error("Failed to calculate occurrences: #{e.message}")
      []
    end
  end
end
