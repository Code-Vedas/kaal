# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'pathname'
require 'kaal'
require 'kaal/rails/version'
require 'kaal/rails/installer'
require 'kaal/rails/railtie'

module Kaal
  # Rails integration surface for Kaal.
  module Rails
    class << self
      DETECT_BACKEND_DEFAULT = Object.new

      def detect_backend_name(db_config = DETECT_BACKEND_DEFAULT)
        db_config = ::ActiveRecord::Base.connection_db_config if db_config.equal?(DETECT_BACKEND_DEFAULT)
        adapter = db_config&.adapter.to_s.downcase

        return 'sqlite' if adapter.include?('sqlite')
        return 'postgres' if adapter.include?('postgres')
        return 'mysql' if adapter.include?('mysql') || adapter.include?('trilogy')

        nil
      rescue ::ActiveRecord::ConnectionNotEstablished
        nil
      end

      def build_backend(backend_name = detect_backend_name)
        case backend_name.to_s
        when 'sqlite'
          Kaal::Backend::SQLite.new
        when 'postgres'
          Kaal::Backend::Postgres.new
        when 'mysql'
          Kaal::Backend::MySQL.new
        end
      end

      def configure_backend!(configuration: Kaal.configuration, backend: build_backend)
        load_config_file!(configuration:)
        logger = configuration.logger
        current_backend = configuration.backend
        selected_backend = current_backend || backend
        return nil unless selected_backend

        configuration.backend = selected_backend unless current_backend
        Kaal.warn_on_risky_configuration!(configuration:, logger:)
        selected_backend
      end

      def load_config_file!(configuration: Kaal.configuration, root: ::Rails.root, environment: ::Rails.env)
        runtime_context = Kaal::Runtime::RuntimeContext.new(root_path: root, environment_name: environment.to_s)
        Kaal::Config::FileLoader.new(configuration:, runtime_context:).load
      end

      def install!(root: ::Rails.root, backend: detect_backend_name)
        installer = Installer.new(root:, backend:)
        {
          runtime_config: installer.install_runtime_config,
          scheduler_config: installer.install_scheduler_config,
          migrations: installer.install_migrations
        }
      end
    end
  end
end
