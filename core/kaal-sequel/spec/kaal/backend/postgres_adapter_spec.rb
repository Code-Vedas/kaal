# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Kaal::Backend::PostgresAdapter do
  let(:connection) do
    Class.new do
      def fetch(sql, *_binds)
        [{ result: sql.include?('try') }]
      end
    end.new
  end
  let(:database) { instance_double(Kaal::Persistence::Database, connection:) }

  before do
    allow(Kaal::Persistence::Database).to receive(:new).and_return(database)
  end

  it 'acquires and releases advisory locks' do
    adapter = described_class.new(:fake)
    allow(adapter).to receive(:log_dispatch_attempt)

    expect(adapter.acquire('key', 10)).to be(true)
    expect(adapter.release('key')).to be(false)
    expect(described_class.send(:calculate_lock_id, 'key')).to be_a(Integer)
    expect(adapter.dispatch_registry).to be_a(Kaal::Dispatch::DatabaseEngine)
    expect(adapter.definition_registry).to be_a(Kaal::Definition::DatabaseEngine)
  end

  it 'wraps adapter errors' do
    broken_connection = Class.new do
      def fetch(*)
        raise 'boom'
      end
    end.new
    allow(Kaal::Persistence::Database).to receive(:new).and_return(instance_double(Kaal::Persistence::Database, connection: broken_connection))

    adapter = described_class.new(:fake)
    expect { adapter.acquire('key', 10) }.to raise_error(Kaal::Backend::LockAdapterError, /PostgreSQL acquire failed/)
    expect { adapter.release('key') }.to raise_error(Kaal::Backend::LockAdapterError, /PostgreSQL release failed/)
  end

  it 'covers unsuccessful lock attempts and signed-id conversion' do
    unsuccessful_connection = Class.new do
      def fetch(sql, *_binds)
        [{ result: sql.include?('try') ? nil : true }]
      end
    end.new
    allow(Kaal::Persistence::Database).to receive(:new).and_return(
      instance_double(Kaal::Persistence::Database, connection: unsuccessful_connection)
    )

    adapter = described_class.new(:fake)
    allow(adapter).to receive(:log_dispatch_attempt)
    expect(adapter.acquire('key', 10)).to be(false)
    expect(adapter.release('key')).to be(true)

    allow(Digest::MD5).to receive(:digest).and_return([Kaal::Backend::PostgresAdapter::SIGNED_64_MAX + 1].pack('Q>'))
    expect(described_class.send(:calculate_lock_id, 'key')).to be < 0
  end
end
