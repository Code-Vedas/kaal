# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
module Kaal
  # Invokes a previously registered signal handler when it is safe to do so.
  class SignalHandlerChain
    RESERVED_COMMAND_HANDLERS = %w[DEFAULT IGNORE].freeze

    def initialize(signal:, previous_handler:, logger:)
      @signal = signal
      @previous_handler = previous_handler
      @logger = logger
    end

    def call(...)
      return unless @previous_handler

      case @previous_handler
      when Proc, Method
        invoke_callable(...)
      when String
        return if RESERVED_COMMAND_HANDLERS.include?(@previous_handler)

        @logger&.debug("Previous #{@signal} handler was a command: #{@previous_handler}")
      end
    end

    private

    def invoke_callable(*args)
      arity = @previous_handler.arity
      return @previous_handler.call if arity.zero?

      argument_length = args.length
      argument_count = arity.negative? ? argument_length : [arity, argument_length].min
      @previous_handler.call(*args.first(argument_count))
    end
  end
end
