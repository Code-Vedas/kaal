# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'

RSpec.describe Kaal do
  let(:engine) do
    double(
      dispatch_registry: :dispatch_registry,
      definition_registry: :definition_registry,
      delayed_store: :delayed_store,
      acquire: true,
      release: true
    )
  end

  it 'builds sequel-backed postgres and mysql adapters' do
    allow(Kaal::Sequel).to receive(:require_sequel!)
    require 'kaal/internal/sequel'
    allow(Kaal::Internal::Sequel::PostgresBackend).to receive(:new).and_return(engine)
    allow(Kaal::Internal::Sequel::MySQLBackend).to receive(:new).and_return(engine)

    postgres = Kaal::Backend::Postgres.new(database: :db)
    mysql = Kaal::Backend::MySQL.new(database: :db, use_skip_locked: true)

    expect(postgres.dispatch_registry).to eq(:dispatch_registry)
    expect(postgres.definition_registry).to eq(:definition_registry)
    expect(postgres.delayed_store).to eq(:delayed_store)
    expect(postgres.acquire('key', 1)).to be(true)
    expect(postgres.release('key')).to be(true)

    expect(mysql.dispatch_registry).to eq(:dispatch_registry)
    expect(mysql.definition_registry).to eq(:definition_registry)
    expect(mysql.delayed_store).to eq(:delayed_store)
    expect(mysql.acquire('key', 1)).to be(true)
    expect(mysql.release('key')).to be(true)
    expect(Kaal::Internal::Sequel::PostgresBackend).to have_received(:new).with(:db, namespace: nil)
    expect(Kaal::Internal::Sequel::MySQLBackend).to have_received(:new).with(:db, namespace: nil, use_skip_locked: true)
  end

  it 'builds active-record-backed postgres and mysql adapters' do
    Kaal::ActiveRecord.require_activerecord!
    allow(Kaal::ActiveRecord).to receive(:require_activerecord!)
    require 'kaal/internal/active_record'
    allow(Kaal::Internal::ActiveRecord::PostgresBackend).to receive(:new).and_return(engine)
    allow(Kaal::Internal::ActiveRecord::MySQLBackend).to receive(:new).and_return(engine)

    postgres = Kaal::Backend::Postgres.new(connection: :connection)
    mysql = Kaal::Backend::MySQL.new(connection: :connection, use_skip_locked: false)

    expect(postgres.delayed_store).to eq(:delayed_store)
    expect(mysql.delayed_store).to eq(:delayed_store)
    expect(Kaal::Internal::ActiveRecord::PostgresBackend).to have_received(:new).with(:connection, namespace: nil)
    expect(Kaal::Internal::ActiveRecord::MySQLBackend).to have_received(:new).with(
      :connection,
      namespace: nil,
      use_skip_locked: false
    )
  end

  it 'rejects unsupported backend keywords at the wrapper layer' do
    expect do
      Kaal::Backend::Postgres.new(database: :db, unsupported: true)
    end.to raise_error(ArgumentError, /unknown keyword: :unsupported/)

    expect do
      Kaal::Backend::MySQL.new(database: :db, unsupported: true)
    end.to raise_error(ArgumentError, /unknown keyword: :unsupported/)
  end
end
