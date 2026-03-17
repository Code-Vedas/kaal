# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Kaal::Backend::MySQLAdapter do
  let(:connection) do
    Class.new do
      attr_reader :calls

      def initialize
        @calls = []
      end

      def fetch(sql, *binds)
        @calls << [sql, binds]
        [{ result: yield_value(sql) }]
      end

      def yield_value(sql)
        return 1 if sql.include?('GET_LOCK')

        1
      end
    end.new
  end
  let(:database) { instance_double(Kaal::Persistence::Database, connection:) }

  before do
    allow(Kaal::Persistence::Database).to receive(:new).and_return(database)
  end

  it 'acquires, releases, and normalizes lock names' do
    adapter = described_class.new(:fake)
    allow(adapter).to receive(:log_dispatch_attempt)

    expect(adapter.acquire('short-key', 10)).to be(true)
    expect(adapter.release('short-key')).to be(true)
    expect(described_class.send(:normalize_lock_name, 'x' * 80)).to match(/\A.{47}:.{16}\z/)
    expect(adapter.dispatch_registry).to be_a(Kaal::Dispatch::DatabaseEngine)
    expect(adapter.definition_registry).to be_a(Kaal::Definition::DatabaseEngine)
  end

  it 'wraps adapter errors' do
    broken_connection = Class.new do
      def fetch(*)
        raise 'boom'
      end
    end.new
    allow(Kaal::Persistence::Database).to receive(:new).and_return(
      instance_double(Kaal::Persistence::Database, connection: broken_connection)
    )

    adapter = described_class.new(:fake)
    expect { adapter.acquire('key', 10) }.to raise_error(Kaal::Backend::LockAdapterError, /MySQL acquire failed/)
    expect { adapter.release('key') }.to raise_error(Kaal::Backend::LockAdapterError, /MySQL release failed/)
  end

  it 'covers unsuccessful named-lock acquisition' do
    unsuccessful_connection = Class.new do
      def fetch(*)
        [{ result: 0 }]
      end
    end.new
    allow(Kaal::Persistence::Database).to receive(:new).and_return(
      instance_double(Kaal::Persistence::Database, connection: unsuccessful_connection)
    )

    adapter = described_class.new(:fake)
    allow(adapter).to receive(:log_dispatch_attempt)
    expect(adapter.acquire('key', 10)).to be(false)
  end
end
