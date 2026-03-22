# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'kaal/runtime/runtime_context'
require 'kaal/runtime/scheduler_boot_loader'
require 'kaal/runtime/signal_handler_chain'
require 'kaal/runtime/signal_handler_installer'

module Kaal
  # Runtime wiring and lifecycle helpers.
  module Runtime
    RuntimeContext = ::Kaal::RuntimeContext
    SchedulerBootLoader = ::Kaal::SchedulerBootLoader
    SignalHandlerChain = ::Kaal::SignalHandlerChain
    SignalHandlerInstaller = ::Kaal::SignalHandlerInstaller
  end
end
