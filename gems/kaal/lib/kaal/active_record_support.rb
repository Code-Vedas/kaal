# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'fileutils'

module Kaal
  # Active Record migration/install support for SQL-backed Kaal backends.
  module ActiveRecord
    module_function

    def install_postgres_migration(target_dir:, migration_name: 'Create Kaal Postgres Backend')
      install_migrations(target_dir:, backend: 'postgres', migration_name:)
    end

    def install_mysql_migration(target_dir:, migration_name: 'Create Kaal MySQL Backend')
      install_migrations(target_dir:, backend: 'mysql', migration_name:)
    end

    def install_sqlite_migration(target_dir:, migration_name: 'Create Kaal SQLite Backend')
      install_migrations(target_dir:, backend: 'sqlite', migration_name:)
    end

    def install_migrations(target_dir:, backend:, migration_name: nil, time_source: -> { Time.now.utc })
      class_name = normalize_migration_name(migration_name, fallback: default_migration_class_for(backend))
      base_path = File.expand_path(target_dir)
      FileUtils.mkdir_p(base_path)
      templates = Kaal::Internal::ActiveRecord::MigrationTemplates.for_backend(backend)

      templates.map.with_index do |(_name, contents), index|
        suffix = underscore(class_name)
        suffix = "#{suffix}_#{migration_suffixes_for(backend).fetch(index)}" if templates.length > 1
        path = File.expand_path("#{(time_source.call + index).strftime('%Y%m%d%H%M%S')}_#{suffix}.rb", base_path)
        File.write(path, contents)
        path
      end
    end

    def require_activerecord!
      require 'active_record'
      require 'active_support/inflector'
    rescue LoadError => e
      raise LoadError,
            "#{e.message}. Add `gem 'activerecord'` to your Gemfile to use Active Record-backed Kaal SQL support.",
            cause: e
    end

    def normalize_migration_name(name, fallback:)
      normalized = name.to_s.each_char.with_object(+'') do |char, buffer|
        if alphanumeric?(char)
          buffer << char
        elsif !buffer.empty? && !buffer.end_with?(' ')
          buffer << ' '
        end
      end.split.map!(&:capitalize).join
      normalized.empty? ? fallback : normalized
    end

    def underscore(value)
      require_activerecord!
      ::ActiveSupport::Inflector.underscore(value)
    end

    def default_migration_class_for(backend)
      "CreateKaal#{backend.capitalize}Backend"
    end

    def migration_suffixes_for(backend)
      return %w[dispatches locks definitions] if backend.to_s == 'sqlite'

      %w[dispatches definitions]
    end

    def alphanumeric?(char)
      char.between?('a', 'z') ||
        char.between?('A', 'Z') ||
        char.between?('0', '9')
    end
  end
end
