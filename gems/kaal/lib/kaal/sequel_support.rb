# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'fileutils'

module Kaal
  # Sequel migration/install support for SQL-backed Kaal backends.
  module Sequel
    module_function

    def install_postgres_migration(target_dir:, migration_name: 'create_kaal_postgres_backend')
      install_migrations(target_dir:, backend: 'postgres', migration_name:)
    end

    def install_mysql_migration(target_dir:, migration_name: 'create_kaal_mysql_backend')
      install_migrations(target_dir:, backend: 'mysql', migration_name:)
    end

    def install_sqlite_migration(target_dir:, migration_name: 'create_kaal_sqlite_backend')
      install_migrations(target_dir:, backend: 'sqlite', migration_name:)
    end

    def install_migrations(target_dir:, backend:, migration_name: nil)
      require_sequel!

      normalized_name = normalize_migration_name(migration_name, fallback: default_migration_name_for(backend))
      base_path = File.expand_path(target_dir)
      FileUtils.mkdir_p(base_path)

      Kaal::Persistence::MigrationTemplates.for_backend(backend).map.with_index do |(_name, contents), index|
        suffix = migration_suffixes_for(backend).fetch(index)
        path = File.expand_path("#{timestamp(index)}_#{normalized_name}_#{suffix}.rb", base_path)
        File.write(path, contents)
        path
      end
    end

    def require_sequel!
      require 'sequel'
    rescue LoadError => e
      raise LoadError,
            "#{e.message}. Add `gem 'sequel'` to your Gemfile to use Sequel-backed Kaal SQL support.",
            cause: e
    end

    def normalize_migration_name(name, fallback:)
      normalized = name.to_s.each_char.with_object(+'') do |char, buffer|
        if letter?(char) || digit?(char)
          buffer << char.downcase
        elsif !buffer.empty? && !buffer.end_with?('_')
          buffer << '_'
        end
      end.delete_suffix('_')
      normalized.empty? ? fallback : normalized
    end

    def default_migration_name_for(backend)
      "create_kaal_#{backend}_backend"
    end

    def migration_suffixes_for(backend)
      return %w[dispatches locks definitions delayed_jobs] if backend.to_s == 'sqlite'

      %w[dispatches definitions delayed_jobs]
    end

    def timestamp(offset = 0)
      (Time.now.utc + offset).strftime('%Y%m%d%H%M%S')
    end

    def letter?(char)
      char.between?('a', 'z') || char.between?('A', 'Z')
    end

    def digit?(char)
      char.between?('0', '9')
    end
  end
end
