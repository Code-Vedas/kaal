# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'pathname'
require 'kaal/sequel'
require 'sinatra/base'
require 'kaal/sinatra/version'

module Kaal
  # Sinatra integration surface for Kaal.
  module Sinatra
    class << self
      def register!(
        app,
        backend: nil,
        database: nil,
        redis: nil,
        scheduler_config_path: 'config/scheduler.yml',
        namespace: nil,
        start_scheduler: false,
        adapter: nil
      )
        configuration = Kaal.configuration
        normalized_scheduler_config_path = scheduler_config_path.to_s.strip
        configuration.scheduler_config_path = normalized_scheduler_config_path unless normalized_scheduler_config_path.empty?
        configuration.namespace = namespace unless namespace.nil?

        configure_backend!(backend:, database:, redis:, adapter:, configuration:)
        load_scheduler_file!(root: root_path_for(app), environment: environment_name_for(app))

        start_managed_scheduler! if start_scheduler
        app
      end

      def configure_backend!(backend: nil, database: nil, redis: nil, adapter: nil, configuration: Kaal.configuration)
        current_backend = configuration.backend
        return current_backend if current_backend

        return configuration.backend = backend if backend
        return configuration.backend = build_redis_backend(redis, configuration) if redis

        explicit_adapter = adapter.to_s.strip
        unless explicit_adapter.empty?
          raise ArgumentError, 'database is required when adapter is provided' unless database

          backend_name = normalize_backend_name(explicit_adapter)
          raise ArgumentError, "Unsupported Sinatra datastore backend: #{adapter.inspect}" unless backend_name

          return configuration.backend = build_backend(backend_name, database)
        end

        return configuration.backend = Kaal::Backend::MemoryAdapter.new unless database

        backend_name = detect_backend_name(database, adapter:)
        raise ArgumentError, 'Unsupported Sinatra datastore backend; use memory, redis, sqlite, postgres, or mysql' unless backend_name

        return configuration.backend = build_backend(backend_name, database)
      end

      def detect_backend_name(database, adapter: nil)
        explicit_adapter = normalize_backend_name(adapter)
        return explicit_adapter if explicit_adapter

        inferred_adapter = database_adapter_name(database)
        normalize_backend_name(inferred_adapter)
      end

      def load_scheduler_file!(root:, environment: nil)
        runtime_context = Kaal::Runtime::RuntimeContext.new(
          root_path: root,
          environment_name: environment || Kaal::Runtime::RuntimeContext.environment_name_from(ENV)
        )

        Kaal::Runtime::SchedulerBootLoader.new(
          configuration_provider: -> { Kaal.configuration },
          logger: Kaal.configuration.logger,
          runtime_context: runtime_context,
          load_scheduler_file: -> { Kaal.load_scheduler_file!(runtime_context:) }
        ).load_on_boot!
      end

      def start!
        Kaal.start!
      end

      def stop!(timeout: 30)
        Kaal.stop!(timeout:)
      end

      private

      def build_redis_backend(redis, configuration)
        Kaal::Backend::RedisAdapter.new(redis, namespace: configuration.namespace)
      end

      def build_backend(backend_name, database)
        case backend_name
        when 'sqlite'
          Kaal::Backend::DatabaseAdapter.new(database)
        when 'postgres'
          Kaal::Backend::PostgresAdapter.new(database)
        when 'mysql'
          Kaal::Backend::MySQLAdapter.new(database)
        end
      end

      def database_adapter_name(database)
        return if database.nil?

        database_type = database.database_type if database.respond_to?(:database_type)
        return database_type.to_s unless database_type.to_s.strip.empty?

        adapter_scheme = database.adapter_scheme if database.respond_to?(:adapter_scheme)
        adapter_scheme.to_s
      end

      def normalize_backend_name(adapter_name)
        adapter = adapter_name.to_s.strip.downcase
        return if adapter.empty?
        return 'sqlite' if adapter.include?('sqlite')
        return 'postgres' if adapter.include?('postgres')
        return 'mysql' if adapter.include?('mysql') || adapter.include?('trilogy')

        nil
      end

      def root_path_for(app)
        settings = settings_for(app)
        root = settings.root if settings.respond_to?(:root)
        Pathname.new(root || Dir.pwd)
      end

      def environment_name_for(app)
        settings = settings_for(app)
        environment = settings.environment if settings.respond_to?(:environment)
        environment.to_s.empty? ? Kaal::Runtime::RuntimeContext.environment_name_from(ENV) : environment.to_s
      end

      def settings_for(app)
        app.respond_to?(:settings) ? app.settings : app
      end

      def start_managed_scheduler!
        return if Kaal.running?

        start!
        install_shutdown_hook
      end

      def install_shutdown_hook
        return if @shutdown_hook_installed

        @shutdown_hook_installed = true
        Kernel.at_exit do
          if Kaal.running?
            begin
              stop!
            rescue StandardError
              nil
            end
          end
        end
      end
    end

    # Sinatra extension that wires Kaal into classic and modular apps.
    module Extension
      def self.registered(app)
        app.extend(ClassMethods)
      end

      # DSL helpers installed onto Sinatra apps.
      module ClassMethods
        def kaal(**)
          Kaal::Sinatra.register!(self, **)
        end
      end
    end
  end
end
