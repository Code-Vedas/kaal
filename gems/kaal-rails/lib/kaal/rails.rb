# frozen_string_literal: true

require 'pathname'
require 'kaal'
require 'kaal/active_record'
require 'kaal/rails/version'
require 'kaal/rails/installer'
require 'kaal/rails/railtie'

module Kaal
  # Rails integration surface for Kaal.
  module Rails
    class << self
      def detect_backend_name(db_config = ::ActiveRecord::Base.connection_db_config)
        adapter = db_config&.adapter.to_s.downcase

        return 'sqlite' if adapter.include?('sqlite')
        return 'postgres' if adapter.include?('postgres')
        return 'mysql' if adapter.include?('mysql')

        nil
      end

      def build_backend(backend_name = detect_backend_name)
        case backend_name.to_s
        when 'sqlite'
          Kaal::ActiveRecord::DatabaseAdapter.new
        when 'postgres'
          Kaal::ActiveRecord::PostgresAdapter.new
        when 'mysql'
          Kaal::ActiveRecord::MySQLAdapter.new
        end
      end

      def configure_backend!(configuration: Kaal.configuration, backend: build_backend)
        current_backend = configuration.backend
        return current_backend if current_backend
        return nil unless backend

        configuration.backend = backend
      end

      def install!(root: ::Rails.root, backend: detect_backend_name)
        installer = Installer.new(root:, backend:)
        {
          scheduler_config: installer.install_scheduler_config,
          migrations: installer.install_migrations
        }
      end
    end
  end
end
