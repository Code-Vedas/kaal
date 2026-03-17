# frozen_string_literal: true

RSpec.describe Kaal::ActiveRecord do
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

  it 'supports sqlite-backed definition, dispatch, and lock persistence' do
    KaalActiveRecordSupport.with_sqlite_database do |connection|
      registry = described_class::DefinitionRegistry.new(connection:)
      dispatch_registry = described_class::DispatchRegistry.new(connection:)
      adapter = described_class::DatabaseAdapter.new(connection)

      expect(registry.upsert_definition(key: 'job:a', cron: '* * * * *', metadata: { 'a' => 1 })[:metadata]).to eq('a' => 1)
      expect(registry.upsert_definition(key: 'job:nil', cron: '* * * * *', metadata: nil)[:metadata]).to eq({})
      expect(registry.disable_definition('job:a')[:enabled]).to be(false)
      first_disabled_at = registry.find_definition('job:a')[:disabled_at]
      expect(first_disabled_at).to be_a(Time)
      expect(registry.upsert_definition(key: 'job:a', cron: '* * * * *', enabled: false)[:disabled_at]).to eq(first_disabled_at)
      expect(registry.enable_definition('job:a')[:enabled]).to be(true)
      expect(registry.enabled_definitions.map { |row| row[:key] }).to eq(%w[job:a job:nil])
      expect(registry.all_definitions.map { |row| row[:key] }).to eq(%w[job:a job:nil])
      expect(registry.find_definition('missing')).to be_nil
      expect(registry.remove_definition('missing')).to be_nil
      expect(registry.remove_definition('job:a')).to include(key: 'job:a')
      expect(registry.all_definitions.map { |row| row[:key] }).to eq(['job:nil'])
      registry.upsert_definition(key: 'job:a', cron: '* * * * *')

      fire_time = Time.utc(2026, 1, 1, 0, 0, 0)
      dispatch_registry.log_dispatch('job:a', fire_time, 'node-1')
      expect(dispatch_registry.find_dispatch('job:a', fire_time)).to include(node_id: 'node-1', status: 'dispatched')
      expect(dispatch_registry.find_by_key('job:a').length).to eq(1)
      expect(dispatch_registry.find_by_node('node-1').length).to eq(1)
      expect(dispatch_registry.find_by_status('dispatched').length).to eq(1)
      expect(dispatch_registry.find_dispatch('job:a', Time.utc(2030, 1, 1))).to be_nil
      expect(dispatch_registry.cleanup(recovery_window: 0)).to eq(1)

      expect(adapter.acquire('lock:1', 60)).to be(true)
      expect(adapter.acquire('lock:1', 60)).to be(false)
      expect(adapter.release('lock:1')).to be(true)
      expect(adapter.release('lock:missing')).to be(false)
      expect(adapter.dispatch_registry).to be_a(described_class::DispatchRegistry)
      expect(adapter.definition_registry).to be_a(described_class::DefinitionRegistry)
    end
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

  it 'supports postgres advisory lock adapters' do
    connection = instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter)
    allow(Kaal::ActiveRecord::BaseRecord).to receive(:connection).and_return(connection)
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
    registry = described_class::DefinitionRegistry.new(connection: nil)
    now = Time.utc(2026, 1, 1, 0, 0, 0)

    new_record = Object.new
    def new_record.persisted? = false

    existing_record = Object.new
    def existing_record.persisted? = true
    existing_record.define_singleton_method(:disabled_at) { now }

    expect(registry.send(:disabled_at_for, new_record, false, now)).to eq(now)
    expect(registry.send(:disabled_at_for, existing_record, false, now + 60)).to eq(now)
  end
end
