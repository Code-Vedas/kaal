# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'active_record'
require 'kaal'
require 'kaal/active_record/version'
require 'kaal/active_record/railtie'
require 'kaal/active_record/connection_support'
require 'kaal/active_record/base_record'
require 'kaal/active_record/definition_record'
require 'kaal/active_record/dispatch_record'
require 'kaal/active_record/lock_record'
require 'kaal/active_record/definition_registry'
require 'kaal/active_record/dispatch_registry'
require 'kaal/active_record/database_adapter'
require 'kaal/active_record/postgres_adapter'
require 'kaal/active_record/mysql_adapter'
require 'kaal/active_record/sqlite_adapter'
require 'kaal/active_record/migration_templates'

module Kaal
  # Active Record-backed datastore adapter namespace for Kaal.
  module ActiveRecord
  end
end
