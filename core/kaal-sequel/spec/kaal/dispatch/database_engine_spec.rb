# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'

RSpec.describe Kaal::Dispatch::DatabaseEngine do
  subject(:engine) { described_class.new(database: db) }

  let(:db) { Sequel.sqlite }

  before do
    db.create_table :kaal_dispatches do
      primary_key :id
      String :key, null: false
      Time :fire_time, null: false
      Time :dispatched_at, null: false
      String :node_id, null: false
      String :status, null: false
    end
    db.add_index :kaal_dispatches, %i[key fire_time], unique: true
    db.add_index :kaal_dispatches, :key
    db.add_index :kaal_dispatches, :node_id
    db.add_index :kaal_dispatches, :status
    db.add_index :kaal_dispatches, :fire_time
  end

  it 'logs, queries, and cleans dispatches' do
    fire_time = Time.now.utc
    older_time = Time.utc(2025, 1, 1, 0, 0, 0)
    engine.log_dispatch('job:a', fire_time, 'node-1')
    engine.log_dispatch('job:b', older_time, 'node-2', 'failed')

    expect(engine.find_dispatch('job:a', fire_time)).to include(node_id: 'node-1')
    expect(engine.find_dispatch('missing', fire_time)).to be_nil
    expect(engine.find_by_key('job:a').length).to eq(1)
    expect(engine.find_by_node('node-2').length).to eq(1)
    expect(engine.find_by_status('failed').length).to eq(1)
    expect(engine.cleanup(recovery_window: 60)).to eq(1)
  end

  it 'falls back to update-or-insert when insert_conflict is unavailable' do
    wrapper_dataset = Class.new do
      def initialize(dataset)
        @dataset = dataset
      end

      def respond_to_missing?(method_name, include_private = false)
        return false if method_name == :insert_conflict

        @dataset.respond_to?(method_name, include_private) || super
      end

      def method_missing(method_name, ...)
        return super if method_name == :insert_conflict

        @dataset.public_send(method_name, ...)
      end
    end.new(db[:kaal_dispatches])
    wrapped_engine = described_class.new(database: db)
    wrapped_engine.instance_variable_set(
      :@database,
      Struct.new(:dispatches_dataset).new(wrapper_dataset)
    )

    fire_time = Time.now.utc
    wrapped_engine.log_dispatch('job:fallback', fire_time, 'node-1')
    wrapped_engine.log_dispatch('job:fallback', fire_time, 'node-2', 'failed')

    expect(wrapped_engine.find_dispatch('job:fallback', fire_time)).to include(node_id: 'node-2', status: 'failed')
  end

  it 'updates an existing dispatch when insert_conflict is unavailable' do
    wrapper_dataset = Class.new do
      def initialize(dataset)
        @dataset = dataset
      end

      def respond_to_missing?(method_name, include_private = false)
        return false if method_name == :insert_conflict

        @dataset.respond_to?(method_name, include_private) || super
      end

      def method_missing(method_name, ...)
        return super if method_name == :insert_conflict

        @dataset.public_send(method_name, ...)
      end
    end.new(db[:kaal_dispatches])
    wrapped_engine = described_class.new(database: db)
    wrapped_engine.instance_variable_set(
      :@database,
      Struct.new(:dispatches_dataset).new(wrapper_dataset)
    )

    fire_time = Time.now.utc
    db[:kaal_dispatches].insert(
      key: 'job:existing',
      fire_time: fire_time,
      dispatched_at: fire_time,
      node_id: 'node-1',
      status: 'dispatched'
    )

    wrapped_engine.log_dispatch('job:existing', fire_time, 'node-2', 'failed')

    expect(wrapped_engine.find_dispatch('job:existing', fire_time)).to include(node_id: 'node-2', status: 'failed')
  end

  it 'rescues unique violations and updates the existing dispatch when insert_conflict is unavailable' do
    wrapper_dataset = Class.new do
      def initialize(dataset)
        @dataset = dataset
      end

      def respond_to_missing?(method_name, include_private = false)
        return false if method_name == :insert_conflict

        @dataset.respond_to?(method_name, include_private) || super
      end

      def insert(_attributes)
        raise Sequel::UniqueConstraintViolation, 'duplicate dispatch'
      end

      def method_missing(method_name, ...)
        return super if method_name == :insert_conflict

        @dataset.public_send(method_name, ...)
      end
    end.new(db[:kaal_dispatches])

    wrapped_engine = described_class.new(database: db)
    wrapped_engine.instance_variable_set(
      :@database,
      Struct.new(:dispatches_dataset).new(wrapper_dataset)
    )

    fire_time = Time.now.utc
    db[:kaal_dispatches].insert(
      key: 'job:race',
      fire_time: fire_time,
      dispatched_at: fire_time,
      node_id: 'node-1',
      status: 'dispatched'
    )

    wrapped_engine.log_dispatch('job:race', fire_time, 'node-2', 'failed')

    expect(wrapped_engine.find_dispatch('job:race', fire_time)).to include(node_id: 'node-2', status: 'failed')
  end

  it 're-raises unrelated NoMethodError exceptions from the insert_conflict path' do
    wrapper_dataset = Class.new do
      def insert_conflict(...)
        Class.new do
          def insert(_attributes)
            raise NoMethodError, "undefined method `missing_insert' for dispatch relation"
          end
        end.new
      end
    end.new

    wrapped_engine = described_class.new(database: db)
    wrapped_engine.instance_variable_set(
      :@database,
      Struct.new(:dispatches_dataset).new(wrapper_dataset)
    )

    expect do
      wrapped_engine.log_dispatch('job:boom', Time.now.utc, 'node-1')
    end.to raise_error(NoMethodError, /missing_insert/)
  end
end
