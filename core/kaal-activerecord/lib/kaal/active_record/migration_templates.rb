# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
module Kaal
  module ActiveRecord
    # Rails migration templates for Active Record-backed Kaal tables.
    module MigrationTemplates
      module_function

      def for_backend(backend)
        case backend.to_s
        when 'sqlite'
          {
            '001_create_kaal_dispatches.rb' => dispatches_template,
            '002_create_kaal_locks.rb' => locks_template,
            '003_create_kaal_definitions.rb' => definitions_template('sqlite')
          }
        when 'postgres'
          {
            '001_create_kaal_dispatches.rb' => dispatches_template,
            '002_create_kaal_definitions.rb' => definitions_template('postgres')
          }
        when 'mysql'
          {
            '001_create_kaal_dispatches.rb' => dispatches_template,
            '002_create_kaal_definitions.rb' => definitions_template('mysql')
          }
        else
          {}
        end
      end

      def dispatches_template
        <<~RUBY
          class CreateKaalDispatches < ActiveRecord::Migration[7.1]
            def change
              create_table :kaal_dispatches do |t|
                t.string :key, null: false
                t.datetime :fire_time, null: false
                t.datetime :dispatched_at, null: false
                t.string :node_id, null: false
                t.string :status, null: false, default: 'dispatched', limit: 50
              end

              add_index :kaal_dispatches, [:key, :fire_time], unique: true
              add_index :kaal_dispatches, :key
              add_index :kaal_dispatches, :node_id
              add_index :kaal_dispatches, :status
              add_index :kaal_dispatches, :fire_time
            end
          end
        RUBY
      end

      def locks_template
        <<~RUBY
          class CreateKaalLocks < ActiveRecord::Migration[7.1]
            def change
              create_table :kaal_locks do |t|
                t.string :key, null: false
                t.datetime :acquired_at, null: false
                t.datetime :expires_at, null: false
              end

              add_index :kaal_locks, :key, unique: true
              add_index :kaal_locks, :expires_at
            end
          end
        RUBY
      end

      def definitions_template(backend)
        metadata_definition =
          if backend == 'mysql'
            't.text :metadata, null: false'
          else
            "t.text :metadata, null: false, default: '{}'"
          end

        <<~RUBY
          class CreateKaalDefinitions < ActiveRecord::Migration[7.1]
            def change
              create_table :kaal_definitions do |t|
                t.string :key, null: false
                t.string :cron, null: false
                t.boolean :enabled, null: false, default: true
                t.string :source, null: false
                #{metadata_definition}
                t.datetime :disabled_at
                t.datetime :created_at, null: false
                t.datetime :updated_at, null: false
              end

              add_index :kaal_definitions, :key, unique: true
              add_index :kaal_definitions, :enabled
              add_index :kaal_definitions, :source
            end
          end
        RUBY
      end
    end
  end
end
