# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'pathname'
require 'kaal/runtime/runtime_context'
require 'kaal/runtime/scheduler_boot_loader'
require 'kaal/runtime/signal_handler_chain'
require 'kaal/runtime/signal_handler_installer'

module Kaal
  ##
  # Railtie class to integrate Kaal with Rails applications.
  # Initializes configuration, sets up the default logger, and handles signal management.
  class Railtie < ::Rails::Railtie
    ##
    # Ensure configuration logger uses Rails.logger when available.
    def self.ensure_logger!
      logger = Rails.logger
      return unless logger

      Kaal.configure do |config|
        config.logger ||= logger
      end
    rescue NoMethodError
      nil
    end

    ##
    # Register signal handlers for graceful shutdown.
    # Captures and chains any previously registered handlers to cooperate with other components.
    def self.register_signal_handlers
      logger = Kaal.logger

      signal_handler_installer.install do |signal, previous_handler|
        handle_shutdown_signal(signal, previous_handler, logger)
      end
    rescue StandardError => e
      logger&.warn("Failed to register signal handlers: #{e.full_message}")
    end

    ##
    # Handle a shutdown signal and chain to previous handler.
    def self.handle_shutdown_signal(signal, old_handler, logger)
      logger&.info("Received #{signal} signal, stopping scheduler...")
      begin
        stopped = Kaal.stop!(timeout: 30)
        logger&.warn('Scheduler did not stop within timeout, thread may still be running') unless stopped
      rescue StandardError => e
        logger&.error("Error stopping scheduler on #{signal} signal: #{e.full_message}")
      end

      SignalHandlerChain.new(signal: signal, previous_handler: old_handler, logger: logger).call
    end

    ##
    # Load scheduler file at boot while respecting missing-file policy.
    def self.load_scheduler_file_on_boot!
      scheduler_boot_loader.load_on_boot!
    end

    def self.resolve_scheduler_path(path)
      runtime_context.resolve_path(path)
    end

    def self.load_scheduler_file_now!
      Kaal.load_scheduler_file!(runtime_context: runtime_context)
    end

    ##
    # Autoload paths for Kaal models and other components
    initializer 'kaal.autoload' do |_app|
      models_path = File.expand_path('../../app/models', __dir__)
      Rails.autoloaders.main.push_dir(models_path)
    end

    ##
    # Initialize Kaal when Rails boots.
    # Sets the default logger to Rails.logger if available.
    initializer 'kaal.configuration' do |_app|
      # Set default logger to Rails.logger if not already configured
      Kaal::Railtie.ensure_logger!
    end

    ##
    # Load gem i18n files into Rails I18n load path for host applications.
    initializer 'kaal.i18n', before: 'i18n.load_path' do |app|
      locales = Dir[File.expand_path('../../config/locales/*.yml', __dir__)]
      app.config.i18n.load_path |= locales
    end

    ##
    # Load rake tasks into host Rails applications.
    rake_tasks do
      load File.expand_path('../tasks/kaal_tasks.rake', __dir__)
    end

    ##
    # Load the default initializer after Rails has finished initialization.
    # This ensures Rails.logger is fully available and sets up signal handlers.
    config.after_initialize do
      # Re-ensure logger is set in case it wasn't available during first initializer
      Kaal::Railtie.ensure_logger!

      # Load scheduler definitions from file when available (or required by policy)
      Kaal::Railtie.load_scheduler_file_on_boot!

      # Register signal handlers for graceful shutdown
      Kaal::Railtie.register_signal_handlers
    end

    ##
    # Handle graceful shutdown when Rails exits.
    def self.handle_shutdown
      return unless Kaal.running?

      logger = Kaal.logger

      logger&.info('Rails is shutting down, stopping Kaal scheduler...')
      begin
        stopped = Kaal.stop!(timeout: 10)
        return if stopped

        pid = Process.pid
        message_array = [
          'Kaal scheduler did not stop within timeout.',
          "Process #{pid} may still be running. You may need to kill it manually with `kill -9 #{pid}`."
        ]
        logger&.warn(message_array.join(' '))
      rescue StandardError => e
        logger&.error("Error stopping scheduler during shutdown: #{e.message}")
      end
    end

    ##
    # Ensure graceful shutdown on Rails shutdown.
    at_exit do
      Kaal::Railtie.handle_shutdown
    end

    def self.runtime_context
      RuntimeContext.from_rails(Rails)
    end

    def self.scheduler_boot_loader
      current_runtime_context = runtime_context

      SchedulerBootLoader.new(
        configuration_provider: -> { Kaal.configuration },
        logger: Kaal.logger,
        runtime_context: current_runtime_context,
        load_scheduler_file: -> { Kaal.load_scheduler_file!(runtime_context: current_runtime_context) }
      )
    end

    def self.signal_handler_installer
      SignalHandlerInstaller.new
    end
  end
end
