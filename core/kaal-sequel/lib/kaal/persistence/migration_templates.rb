# frozen_string_literal: true

module Kaal
  module Persistence
    # Sequel migration templates emitted by `kaal init`.
    module MigrationTemplates
      module_function

      def for_backend(backend)
        case backend.to_s
        when 'sqlite'
          {
            '001_create_kaal_dispatches.rb' => dispatches_template,
            '002_create_kaal_locks.rb' => locks_template,
            '003_create_kaal_definitions.rb' => definitions_template
          }
        when 'postgres', 'mysql'
          {
            '001_create_kaal_dispatches.rb' => dispatches_template,
            '002_create_kaal_definitions.rb' => definitions_template
          }
        else
          {}
        end
      end

      def dispatches_template
        <<~RUBY
          Sequel.migration do
            change do
              create_table?(:kaal_dispatches) do
                primary_key :id
                String :key, null: false
                Time :fire_time, null: false
                Time :dispatched_at, null: false
                String :node_id, null: false
                String :status, null: false, default: 'dispatched', size: 50
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
          Sequel.migration do
            change do
              create_table?(:kaal_locks) do
                primary_key :id
                String :key, null: false
                Time :acquired_at, null: false
                Time :expires_at, null: false
              end

              add_index :kaal_locks, :key, unique: true
              add_index :kaal_locks, :expires_at
            end
          end
        RUBY
      end

      def definitions_template
        <<~RUBY
          Sequel.migration do
            change do
              create_table?(:kaal_definitions) do
                primary_key :id
                String :key, null: false
                String :cron, null: false
                TrueClass :enabled, null: false, default: true
                String :source, null: false
                String :metadata, text: true, null: false, default: '{}'
                Time :disabled_at
                Time :created_at, null: false
                Time :updated_at, null: false
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
