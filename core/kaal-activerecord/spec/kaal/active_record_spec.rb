# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe Kaal::ActiveRecord do
  def build_definition_record(key: 'job:a', enabled: true, metadata: '{"a":1}')
    Class.new(Struct.new(:key, :cron, :enabled, :source, :metadata, :created_at, :updated_at, :disabled_at)) do
      def persisted?
        false
      end

      def save!
        nil
      end

      def destroy!
        nil
      end
    end.new(
      key,
      '* * * * *',
      enabled,
      'code',
      metadata,
      Time.utc(2026, 1, 1, 0, 0, 0),
      Time.utc(2026, 1, 1, 0, 1, 0),
      nil
    )
  end

  def build_dispatch_record(fire_time:, dispatched_at:, key: 'job:a', node_id: 'node-1', status: 'dispatched')
    Class.new(Struct.new(:key, :fire_time, :dispatched_at, :node_id, :status)) do
      def save!
        nil
      end
    end.new(
      key,
      fire_time,
      dispatched_at,
      node_id,
      status
    )
  end

  it 'has a version number and loads the railtie' do
    expect(Kaal::ActiveRecord::VERSION).to eq('0.2.1')
    expect(Kaal::ActiveRecord::Railtie).to be < Rails::Railtie
    expect(Kaal::ActiveRecord::SQLiteAdapter).to eq(Kaal::ActiveRecord::DatabaseAdapter)
  end

  it 'provides active record migration templates for sql backends' do
    sqlite_templates = described_class::MigrationTemplates.for_backend(:sqlite)
    postgres_templates = described_class::MigrationTemplates.for_backend(:postgres)
    mysql_templates = described_class::MigrationTemplates.for_backend(:mysql)

    expect(sqlite_templates.keys).to eq(
      %w[001_create_kaal_dispatches.rb 002_create_kaal_locks.rb 003_create_kaal_definitions.rb]
    )
    expect(postgres_templates.keys).to eq(
      %w[001_create_kaal_dispatches.rb 002_create_kaal_definitions.rb]
    )
    expect(mysql_templates.keys).to eq(
      %w[001_create_kaal_dispatches.rb 002_create_kaal_definitions.rb]
    )
    expect(postgres_templates.fetch('002_create_kaal_definitions.rb')).to include("t.text :metadata, null: false, default: '{}'")
    expect(mysql_templates.fetch('002_create_kaal_definitions.rb')).to include('t.text :metadata, null: false')
    expect(mysql_templates.fetch('002_create_kaal_definitions.rb')).not_to include("t.text :metadata, null: false, default: '{}'")
    expect(described_class::MigrationTemplates.for_backend(:memory)).to eq({})
  end

  it 'configures or reuses the base record connection' do
    connection = { adapter: 'sqlite3', database: ':memory:' }
    connection_config_class = Struct.new(:configuration_hash, :url)
    database_config_class = Struct.new(:configuration_hash, :url)
    config_object = instance_double(connection_config_class, configuration_hash: connection.stringify_keys, url: nil)
    db_config = instance_double(database_config_class, configuration_hash: connection.stringify_keys, url: nil)
    url_connection = 'sqlite3::memory:'
    url_db_config = instance_double(
      database_config_class,
      configuration_hash: connection.stringify_keys,
      url: url_connection
    )
    config_without_url = Object.new
    config_without_url.define_singleton_method(:configuration_hash) { connection.stringify_keys }

    expect(described_class::ConnectionSupport.configure!).to eq(described_class::BaseRecord)
    allow(described_class::BaseRecord).to receive(:connection_db_config).and_raise(ActiveRecord::ConnectionNotEstablished)
    allow(described_class::BaseRecord).to receive(:establish_connection).with(connection).and_return(true)
    expect(described_class::ConnectionSupport.configure!(connection)).to eq(described_class::BaseRecord)
    expect(described_class::BaseRecord).to have_received(:establish_connection).with(connection)

    allow(described_class::BaseRecord).to receive(:connection_db_config).and_return(db_config)
    expect(described_class::ConnectionSupport.configure!(connection)).to eq(described_class::BaseRecord)
    expect(described_class::BaseRecord).to have_received(:establish_connection).with(connection).once

    allow(described_class::BaseRecord).to receive(:establish_connection).with(config_object).and_return(true)
    allow(described_class::BaseRecord).to receive(:connection_db_config).and_raise(ActiveRecord::ConnectionNotEstablished)
    expect(described_class::ConnectionSupport.configure!(config_object)).to eq(described_class::BaseRecord)
    expect(described_class::BaseRecord).to have_received(:establish_connection).with(config_object)

    expect(described_class::ConnectionSupport.normalize_connection_config(connection)).to eq(connection.merge(adapter: 'sqlite3'))
    expect(described_class::ConnectionSupport.normalize_connection_config(config_object)).to eq(connection)
    expect(described_class::ConnectionSupport.normalize_connection_config(config_without_url)).to eq(connection)
    expect(described_class::ConnectionSupport.normalize_connection_config(url_connection)).to eq(url: url_connection)
    expect(
      described_class::ConnectionSupport.normalize_connection_config('adapter' => 'SQLite3', 'port' => '5432')
    ).to eq(adapter: 'sqlite3', port: 5432)
    expect(
      described_class::ConnectionSupport.normalize_connection_config('adapter' => 'SQLite3', 'port' => 'not-a-number')
    ).to eq(adapter: 'sqlite3', port: 'not-a-number')

    allow(described_class::BaseRecord).to receive(:connection_db_config).and_return(nil)
    expect(described_class::ConnectionSupport.current_connection_config).to be_nil

    allow(described_class::BaseRecord).to receive(:connection_db_config).and_return(db_config)
    expect(described_class::ConnectionSupport.current_connection_config).to eq(connection)

    allow(described_class::BaseRecord).to receive(:connection_db_config).and_return(url_db_config)
    expect(described_class::ConnectionSupport.current_connection_config).to eq(connection.merge(adapter: 'sqlite3', url: url_connection))

    allow(described_class::BaseRecord).to receive(:connection_db_config).and_return(url_db_config)
    expect(described_class::ConnectionSupport.configure!(url_connection)).to eq(described_class::BaseRecord)
    expect(described_class::BaseRecord).to have_received(:establish_connection).with(config_object).once

    other_url_connection = 'sqlite3:other:memory:'
    allow(described_class::BaseRecord).to receive(:establish_connection).with(other_url_connection).and_return(true)
    expect(described_class::ConnectionSupport.configure!(other_url_connection)).to eq(described_class::BaseRecord)
    expect(described_class::BaseRecord).to have_received(:establish_connection).with(other_url_connection)
  end

  it 'matches equivalent connection configs predictably' do
    url_connection = 'sqlite3::memory:'
    other_url_connection = 'sqlite3:other:memory:'

    expect(described_class::ConnectionSupport.configs_match?({ adapter: 'sqlite3' }, { adapter: 'sqlite3' })).to be(true)
    expect(
      described_class::ConnectionSupport.configs_match?({ url: url_connection, adapter: 'sqlite3' }, { url: url_connection })
    ).to be(true)
    expect(
      described_class::ConnectionSupport.configs_match?({ url: url_connection }, { url: other_url_connection })
    ).to be(false)
    expect(
      described_class::ConnectionSupport.configs_match?({ adapter: 'sqlite3' }, { url: url_connection })
    ).to be(false)
    expect(
      described_class::ConnectionSupport.configs_match?(url_connection, { url: url_connection })
    ).to be(false)
    expect(
      described_class::ConnectionSupport.configs_match?({ url: url_connection }, url_connection)
    ).to be(false)
  end

  it 'persists and queries definitions through the registry model interface' do
    model = class_double(described_class::DefinitionRecord)
    record = build_definition_record
    enabled_relation = instance_double(ActiveRecord::Relation)

    allow(model).to receive(:find_or_initialize_by).with(key: 'job:a').and_return(record)
    allow(model).to receive(:find_by).with(key: 'job:a').and_return(record)
    allow(model).to receive(:find_by).with(key: 'missing').and_return(nil)
    allow(model).to receive(:order).with(:key).and_return([record])
    allow(model).to receive(:where).with(enabled: true).and_return(enabled_relation)
    allow(enabled_relation).to receive(:order).with(:key).and_return([record])

    registry = described_class::DefinitionRegistry.new(connection: nil, model:)

    expect(registry.upsert_definition(key: 'job:a', cron: '* * * * *', metadata: { a: 1 })).to include(metadata: { a: 1 })
    expect(registry.find_definition('job:a')).to include(key: 'job:a')
    expect(registry.find_definition('missing')).to be_nil
    record.enabled = false
    expect(registry.find_definition('job:a')).to include(enabled: false)
    record.enabled = true
    expect(registry.all_definitions).to contain_exactly(hash_including(key: 'job:a'))
    expect(registry.enabled_definitions).to contain_exactly(hash_including(key: 'job:a'))
    expect(registry.remove_definition('job:a')).to include(key: 'job:a')
    expect(registry.remove_definition('missing')).to be_nil
  end

  it 'persists and queries dispatches through the registry model interface' do
    model = class_double(described_class::DispatchRecord)
    fire_time = Time.utc(2026, 1, 1, 0, 0, 0)
    dispatched_at = Time.utc(2026, 1, 1, 0, 1, 0)
    record = build_dispatch_record(fire_time:, dispatched_at:)
    filtered_relation = instance_double(ActiveRecord::Relation)
    cleanup_relation = instance_double(ActiveRecord::Relation, delete_all: 1)

    allow(model).to receive(:find_or_initialize_by).with(key: 'job:a', fire_time:).and_return(record)
    allow(model).to receive(:find_by).with(key: 'job:a', fire_time:).and_return(record)
    allow(model).to receive(:find_by).with(key: 'missing', fire_time:).and_return(nil)
    allow(model).to receive(:where).and_return(filtered_relation)
    allow(model).to receive(:where).with(fire_time: kind_of(Range)).and_return(cleanup_relation)
    allow(filtered_relation).to receive(:order).with(fire_time: :desc).and_return([record])

    registry = described_class::DispatchRegistry.new(connection: nil, model:)

    expect(registry.log_dispatch('job:a', fire_time, 'node-1')).to include(node_id: 'node-1')
    expect(registry.find_dispatch('job:a', fire_time)).to include(status: 'dispatched')
    expect(registry.find_dispatch('missing', fire_time)).to be_nil
    expect(registry.method(:find_by_key).call('job:a')).to contain_exactly(hash_including(key: 'job:a'))
    expect(registry.method(:find_by_node).call('node-1')).to contain_exactly(hash_including(node_id: 'node-1'))
    expect(registry.method(:find_by_status).call('dispatched')).to contain_exactly(hash_including(status: 'dispatched'))
    expect(registry.cleanup(recovery_window: 0)).to eq(1)
  end

  it 'wraps sqlite lock adapter failures' do
    lock_model = class_double(Kaal::ActiveRecord::LockRecord).as_stubbed_const
    relation = instance_double(ActiveRecord::Relation, delete_all: 0)
    allow(lock_model).to receive(:where).and_return(relation)
    allow(lock_model).to receive(:create!).and_raise(StandardError, 'create boom')
    allow(relation).to receive(:delete_all).and_raise(StandardError, 'delete boom')

    adapter = described_class::DatabaseAdapter.new(nil, lock_model:)

    expect { adapter.acquire('lock:1', 60) }.to raise_error(Kaal::Backend::LockAdapterError, /Database acquire failed/)
    expect { adapter.release('lock:1') }.to raise_error(Kaal::Backend::LockAdapterError, /Database release failed/)
  end

  it 'returns false when sqlite lock acquisition collides twice' do
    lock_model = class_double(Kaal::ActiveRecord::LockRecord).as_stubbed_const
    relation = instance_double(ActiveRecord::Relation, delete_all: 1)
    allow(lock_model).to receive(:where).and_return(relation)
    allow(lock_model).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)

    adapter = described_class::DatabaseAdapter.new(nil, lock_model:)

    expect(adapter.acquire('lock:1', 60)).to be(false)
  end

  it 'acquires sqlite locks successfully on the first attempt' do
    lock_model = class_double(Kaal::ActiveRecord::LockRecord).as_stubbed_const
    allow(lock_model).to receive(:create!).and_return(true)

    adapter = described_class::DatabaseAdapter.new(nil, lock_model:)
    allow(adapter).to receive(:log_dispatch_attempt)

    expect(adapter.acquire('lock:1', 60)).to be(true)
    expect(adapter).to have_received(:log_dispatch_attempt).with('lock:1')
  end

  it 'builds default registry accessors for the database adapter' do
    allow(described_class::DispatchRegistry).to receive(:new).and_return(:dispatch_registry)
    allow(described_class::DefinitionRegistry).to receive(:new).and_return(:definition_registry)

    adapter = described_class::DatabaseAdapter.new(nil, lock_model: class_double(described_class::LockRecord))

    expect(adapter.dispatch_registry).to eq(:dispatch_registry)
    expect(adapter.definition_registry).to eq(:definition_registry)
  end

  it 'supports postgres advisory lock adapters' do
    connection = instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter)
    allow(Kaal::ActiveRecord::BaseRecord).to receive(:connection).and_return(connection)
    allow(Kaal::ActiveRecord::BaseRecord).to receive(:sanitize_sql_array) { |parts| parts.first.sub('?', parts.last.to_s) }
    allow(connection).to receive(:exec_query).and_return([{ 'acquired' => true }], [{ 'released' => true }], [{ 'acquired' => false }])

    adapter = described_class::PostgresAdapter.new

    expect(adapter.acquire('lock:pg', 60)).to be(true)
    expect(adapter.release('lock:pg')).to be(true)
    expect(adapter.acquire('lock:pg', 60)).to be(false)
    expect(adapter.dispatch_registry).to be_a(described_class::DispatchRegistry)
    expect(adapter.definition_registry).to be_a(described_class::DefinitionRegistry)
    expect(described_class::PostgresAdapter.calculate_lock_id('lock:pg')).to be_a(Integer)
    allow(Digest::MD5).to receive(:digest).and_return([described_class::PostgresAdapter::SIGNED_64_MAX + 1].pack('Q>'))
    expect(described_class::PostgresAdapter.calculate_lock_id('lock:pg')).to be < 0

    allow(connection).to receive(:exec_query).and_raise(StandardError, 'boom')
    expect { adapter.acquire('lock:pg', 60) }.to raise_error(Kaal::Backend::LockAdapterError, /PostgreSQL acquire failed/)
    expect { adapter.release('lock:pg') }.to raise_error(Kaal::Backend::LockAdapterError, /PostgreSQL release failed/)
  end

  it 'supports mysql named lock adapters and lock name normalization' do
    connection = instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter)
    allow(Kaal::ActiveRecord::BaseRecord).to receive(:connection).and_return(connection)
    allow(Kaal::ActiveRecord::BaseRecord).to receive(:sanitize_sql_array) { |parts| parts.first.sub('?', "'#{parts.last}'") }
    allow(connection).to receive(:exec_query).and_return([{ 'lock_result' => 1 }], [{ 'lock_result' => 1 }], [{ 'lock_result' => 0 }])

    adapter = described_class::MySQLAdapter.new

    expect(adapter.acquire('short-key', 60)).to be(true)
    expect(adapter.release('short-key')).to be(true)
    expect(adapter.acquire('short-key', 60)).to be(false)
    expect(adapter.dispatch_registry).to be_a(described_class::DispatchRegistry)
    expect(adapter.definition_registry).to be_a(described_class::DefinitionRegistry)
    expect(described_class::MySQLAdapter.normalize_lock_name('short-key')).to eq('short-key')
    expect(described_class::MySQLAdapter.normalize_lock_name('x' * 100).length).to be <= described_class::MySQLAdapter::MAX_LOCK_NAME_LENGTH

    allow(connection).to receive(:exec_query).and_raise(StandardError, 'boom')
    expect { adapter.acquire('short-key', 60) }.to raise_error(Kaal::Backend::LockAdapterError, /MySQL acquire failed/)
    expect { adapter.release('short-key') }.to raise_error(Kaal::Backend::LockAdapterError, /MySQL release failed/)
  end

  it 'preserves disabled_at helper behavior for new and existing records' do
    model = class_double(described_class::DefinitionRecord)
    now = Time.utc(2026, 1, 1, 0, 0, 0)

    new_record = build_definition_record(enabled: true)
    existing_record = build_definition_record(enabled: false)
    existing_record.disabled_at = now
    existing_record.define_singleton_method(:persisted?) { true }

    allow(Time).to receive(:now).and_return(now, now + 60)
    allow(model).to receive(:find_or_initialize_by).with(key: 'new').and_return(new_record)
    allow(model).to receive(:find_or_initialize_by).with(key: 'existing').and_return(existing_record)

    registry = described_class::DefinitionRegistry.new(connection: nil, model:)

    expect(registry.upsert_definition(key: 'new', cron: '* * * * *', enabled: false)[:disabled_at]).to eq(now)
    expect(registry.upsert_definition(key: 'existing', cron: '* * * * *', enabled: false)[:disabled_at]).to eq(now)
  end

  it 'omits mysql text defaults in test schema helpers' do
    connection = instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter, adapter_name: 'Mysql2')
    table_definition = instance_spy(ActiveRecord::ConnectionAdapters::TableDefinition)
    allow(connection).to receive(:create_table).with(:kaal_definitions).and_yield(table_definition)
    allow(connection).to receive(:add_index)

    KaalActiveRecordSupport.create_definitions_table(connection)

    expect(table_definition).to have_received(:text).with(:metadata, null: false)
  end
end
