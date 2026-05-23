# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'kaal/internal/active_record/base_record'
require 'kaal/internal/active_record/connection_support'
require 'kaal/internal/active_record/definition_record'
require 'kaal/internal/active_record/dispatch_record'
require 'kaal/internal/active_record/delayed_job_record'
require 'kaal/internal/active_record/lock_record'
require 'kaal/internal/active_record/definition_registry'
require 'kaal/internal/active_record/dispatch_registry'
require 'kaal/internal/active_record/delayed_job_registry'
require 'kaal/internal/active_record/database_backend'
require 'kaal/internal/active_record/postgres_backend'
require 'kaal/internal/active_record/mysql_backend'
require 'kaal/internal/active_record/migration_templates'
