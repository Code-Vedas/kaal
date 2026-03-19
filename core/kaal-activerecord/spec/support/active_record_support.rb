# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'cgi'
require 'uri'

module KaalActiveRecordSupport
  module_function

  def with_sqlite_database
    Dir.mktmpdir('kaal-activerecord-') do |root|
      database_path = File.join(root, 'kaal.sqlite3')
      connection = { adapter: 'sqlite3', database: database_path }
      Kaal::ActiveRecord::ConnectionSupport.configure!(connection)
      create_schema!(locks: true)
      yield connection
    end
  end

  def create_schema!(locks:)
    connection = Kaal::ActiveRecord::BaseRecord.connection
    drop_tables(connection)
    create_dispatches_table(connection)
    create_locks_table(connection) if locks
    create_definitions_table(connection)
  end

  def reset_database!(database_url)
    uri = URI.parse(database_url.gsub('\\!', '!'))
    database_name = uri.path.delete_prefix('/')
    admin_url = build_admin_database_url(uri)
    admin_connection = admin_connection_for(admin_url)

    case uri.scheme
    when 'postgres', 'postgresql'
      admin_connection.execute(<<~SQL)
        SELECT pg_terminate_backend(pid)
        FROM pg_stat_activity
        WHERE datname = #{admin_connection.quote(database_name)}
          AND pid <> pg_backend_pid()
      SQL
      admin_connection.execute("DROP DATABASE IF EXISTS #{database_name}")
      admin_connection.execute("CREATE DATABASE #{database_name}")
    when 'mysql2'
      admin_connection.execute("DROP DATABASE IF EXISTS `#{database_name}`")
      admin_connection.execute("CREATE DATABASE `#{database_name}`")
    else
      raise ArgumentError, "Unsupported adapter: #{uri.scheme}"
    end
  end

  def connect!(database_url)
    Kaal::ActiveRecord::ConnectionSupport.configure!(database_url.gsub('\\!', '!'))
  end

  def drop_tables(connection)
    connection.drop_table(:kaal_locks, if_exists: true)
    connection.drop_table(:kaal_dispatches, if_exists: true)
    connection.drop_table(:kaal_definitions, if_exists: true)
  end

  def create_dispatches_table(connection)
    connection.create_table :kaal_dispatches do |t|
      t.string :key, null: false
      t.datetime :fire_time, null: false
      t.datetime :dispatched_at, null: false
      t.string :node_id, null: false
      t.string :status, null: false, default: 'dispatched', limit: 50
    end
    connection.add_index :kaal_dispatches, %i[key fire_time], unique: true
    connection.add_index :kaal_dispatches, :key
    connection.add_index :kaal_dispatches, :node_id
    connection.add_index :kaal_dispatches, :status
    connection.add_index :kaal_dispatches, :fire_time
  end

  def create_locks_table(connection)
    connection.create_table :kaal_locks do |t|
      t.string :key, null: false
      t.datetime :acquired_at, null: false
      t.datetime :expires_at, null: false
    end
    connection.add_index :kaal_locks, :key, unique: true
    connection.add_index :kaal_locks, :expires_at
  end

  def create_definitions_table(connection)
    metadata_options = { null: false }
    metadata_options[:default] = '{}' unless mysql_connection?(connection)

    connection.create_table :kaal_definitions do |t|
      t.string :key, null: false
      t.string :cron, null: false
      t.boolean :enabled, null: false, default: true
      t.string :source, null: false
      t.text :metadata, **metadata_options
      t.datetime :disabled_at
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
    end
    connection.add_index :kaal_definitions, :key, unique: true
    connection.add_index :kaal_definitions, :enabled
    connection.add_index :kaal_definitions, :source
  end

  def build_admin_database_url(uri)
    path = ('/postgres' if uri.scheme.start_with?('postgres'))

    URI::Generic.build(
      scheme: uri.scheme,
      userinfo: uri.userinfo,
      host: uri.host,
      port: uri.port,
      path: path,
      query: uri.query
    ).to_s
  end

  def admin_connection_for(admin_url)
    connection_target = ::ActiveRecord::Base.establish_connection(admin_url)

    if connection_target.respond_to?(:lease_connection)
      connection_target.lease_connection
    elsif connection_target.respond_to?(:connection)
      connection_target.connection
    else
      ::ActiveRecord::Base.connection
    end
  end

  def mysql_connection?(connection)
    connection.adapter_name.to_s.downcase.include?('mysql')
  end
end
