# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
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
