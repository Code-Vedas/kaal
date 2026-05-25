# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'fileutils'
require 'pathname'
require 'uri'

module Kaal
  module Config
    # Builds backend adapter instances from symbolic runtime configuration.
    module BackendFactory
      module_function

      SUPPORTED_BACKENDS = %w[memory redis sqlite postgres mysql].freeze

      def normalize_name(name)
        normalized = name.to_s.strip.downcase
        return nil if normalized.empty?

        normalized = 'postgres' if normalized == 'postgresql'
        normalized = 'mysql' if normalized == 'trilogy'
        return normalized if SUPPORTED_BACKENDS.include?(normalized)

        raise Kaal::ConfigurationError, "Unsupported backend #{name.inspect}; use memory, redis, sqlite, postgres, or mysql"
      end

      def build(name, backend_config:, namespace:, runtime_context: nil)
        backend_name = normalize_name(name)
        config = normalize_backend_config(backend_config)

        case backend_name
        when 'memory'
          Kaal::Backend::MemoryAdapter.new
        when 'redis'
          build_redis_backend(config, namespace)
        when 'sqlite'
          build_sqlite_backend(config, namespace, runtime_context)
        when 'postgres'
          build_postgres_backend(config, namespace)
        when 'mysql'
          build_mysql_backend(config, namespace)
        end
      end

      def normalize_backend_config(backend_config)
        hash = backend_config.is_a?(Hash) ? backend_config : {}
        Kaal::Support::HashTools.symbolize_keys(Kaal::Support::HashTools.deep_dup(hash))
      end

      def build_redis_backend(config, namespace)
        require_redis!

        url = string_value(config[:url])
        raise Kaal::ConfigurationError, 'redis backend requires backend_config.url or KAAL_BACKEND_URL' if url.empty?

        Kaal::Backend::RedisAdapter.new(::Redis.new(url: url), namespace:)
      end

      def build_sqlite_backend(config, namespace, runtime_context)
        return Kaal::Backend::SQLite.new(connection: build_sqlite_connection(config[:connection], runtime_context), namespace:) if config.key?(:connection)

        url = string_value(config[:url])
        database = string_value(config[:database])
        target = url.empty? ? database : url
        raise Kaal::ConfigurationError, 'sqlite backend requires backend_config.url, backend_config.database, or KAAL_BACKEND_URL' if target.empty?

        require_sequel!
        Kaal::Backend::SQLite.new(
          database: sequel_sqlite_database(target, runtime_context),
          namespace:
        )
      end

      def build_postgres_backend(config, namespace)
        if config.key?(:connection)
          return Kaal::Backend::Postgres.new(connection: normalize_connection_hash(config[:connection], 'postgresql', nil),
                                             namespace:)
        end

        url = string_value(config[:url])
        raise Kaal::ConfigurationError, 'postgres backend requires backend_config.url or KAAL_BACKEND_URL' if url.empty?

        require_sequel!
        Kaal::Backend::Postgres.new(database: ::Sequel.connect(url), namespace:)
      end

      def build_mysql_backend(config, namespace)
        use_skip_locked = config[:use_skip_locked]
        skip_locked_configured = config.key?(:use_skip_locked)

        if config.key?(:connection)
          connection = normalize_connection_hash(config[:connection], 'mysql2', nil)
          return Kaal::Backend::MySQL.new(connection:, namespace:) unless skip_locked_configured

          return Kaal::Backend::MySQL.new(connection:, namespace:, use_skip_locked:)
        end

        url = string_value(config[:url])
        raise Kaal::ConfigurationError, 'mysql backend requires backend_config.url or KAAL_BACKEND_URL' if url.empty?

        require_sequel!
        database = ::Sequel.connect(url)
        return Kaal::Backend::MySQL.new(database:, namespace:) unless skip_locked_configured

        Kaal::Backend::MySQL.new(database:, namespace:, use_skip_locked:)
      end

      def build_sqlite_connection(connection, runtime_context)
        normalize_connection_hash(connection, 'sqlite3', runtime_context)
      end

      def normalize_connection_hash(connection, default_adapter, runtime_context)
        case connection
        when String
          connection
        when Hash
          normalized = Kaal::Support::HashTools.symbolize_keys(Kaal::Support::HashTools.deep_dup(connection))
          adapter = string_value(normalized[:adapter])
          normalized_adapter = adapter.empty? ? default_adapter : adapter
          normalized[:adapter] = normalized_adapter
          normalized[:database] = resolve_sqlite_database_path(normalized[:database], runtime_context) if normalized_adapter == 'sqlite3'
          normalized
        else
          raise Kaal::ConfigurationError, 'backend_config.connection must be a URL string or hash'
        end
      end

      def resolve_sqlite_database_path(database, runtime_context)
        value = string_value(database)
        return value if value.empty?
        return value if sqlite_uri?(value)
        return ensure_sqlite_directory!(value) if Pathname.new(value).absolute?

        resolved = runtime_context ? runtime_context.resolve_path(value) : value
        ensure_sqlite_directory!(resolved)
      end

      def sqlite_uri?(value)
        value.start_with?('sqlite:', 'file:')
      end

      def sequel_sqlite_database(target, runtime_context)
        return ::Sequel.connect(target) if sqlite_uri?(target)

        ::Sequel.connect(adapter: 'sqlite', database: resolve_sqlite_database_path(target, runtime_context))
      end

      def ensure_sqlite_directory!(database_path)
        directory = File.dirname(database_path)
        FileUtils.mkdir_p(directory) unless directory == '.' || directory.empty?
        database_path
      end

      def adapter_name_for_error(adapter)
        adapter == 'postgresql' ? 'postgres' : 'mysql'
      end

      def string_value(value)
        value.to_s.strip
      end

      def require_redis!
        require 'redis'
      rescue LoadError => e
        raise LoadError, "#{e.message}. Add `gem 'redis'` to your Gemfile to use the Redis-backed Kaal adapter.", cause: e
      end

      def require_sequel!
        require 'sequel'
      rescue LoadError => e
        raise LoadError, "#{e.message}. Add `gem 'sequel'` to your Gemfile to use Sequel-backed Kaal SQL support.", cause: e
      end
    end
  end
end
