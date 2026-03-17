# frozen_string_literal: true

require 'kaal'
require 'sequel'
require_relative 'sequel/version'
require_relative 'backend/database_adapter'
require_relative 'backend/postgres_adapter'
require_relative 'backend/mysql_adapter'
require_relative 'backend/sqlite_adapter'
require_relative 'definition/persistence_helpers'
require_relative 'definition/database_engine'
require_relative 'dispatch/database_engine'
require_relative 'persistence/database'
require_relative 'persistence/migration_templates'

module Kaal
  module Sequel
    # Base error namespace for Sequel-backed Kaal integrations.
    class Error < StandardError; end
  end
end
