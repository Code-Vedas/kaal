# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Kaal
  # Installs signal handlers while preserving the previous handlers for chaining.
  class SignalHandlerInstaller
    SIGNALS = %w[TERM INT].freeze
    IGNORE_HANDLER = 'IGNORE'

    def initialize(signal_module: Signal)
      @signal_module = signal_module
    end

    def install(signals: SIGNALS)
      signals.each_with_object({}) do |signal, previous_handlers|
        previous_handler = capture_previous_handler(signal)
        @signal_module.trap(signal) { yield(signal, previous_handler) }
        previous_handlers[signal] = previous_handler
      end
    end

    private

    def capture_previous_handler(signal)
      previous_handler = @signal_module.trap(signal, IGNORE_HANDLER)
      restore_previous_handler(signal, previous_handler)
      previous_handler
    end

    def restore_previous_handler(signal, previous_handler)
      return unless previous_handler && previous_handler != IGNORE_HANDLER

      @signal_module.trap(signal, previous_handler)
    end
  end
end
