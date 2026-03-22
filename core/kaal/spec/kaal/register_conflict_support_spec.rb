# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'

RSpec.describe Kaal::RegisterConflictSupport do
  let(:configuration) { Kaal::Configuration.new }
  let(:definition_registry) { Kaal::Definition::MemoryEngine.new }
  let(:registry) { Kaal::Registry.new }
  let(:host) do
    Class.new do
      include Kaal::RegisterConflictSupport

      attr_reader :configuration, :definition_registry, :registry

      def initialize(configuration:, definition_registry:, registry:)
        @configuration = configuration
        @definition_registry = definition_registry
        @registry = registry
      end

      def rollback_registered_definition(*)
        nil
      end
    end.new(configuration:, definition_registry:, registry:)
  end

  it 'returns nil for non-file conflicts and handles file-wins without a logger' do
    expect(
      host.send(
        :resolve_register_conflict,
        key: 'job:a',
        cron: '* * * * *',
        enqueue: ->(**) {},
        existing_definition: nil,
        existing_entry: nil
      )
    ).to be_nil

    expect(
      host.send(
        :resolve_register_conflict,
        key: 'job:a',
        cron: '* * * * *',
        enqueue: ->(**) {},
        existing_definition: { source: 'code' },
        existing_entry: nil
      )
    ).to be_nil

    configuration.scheduler_conflict_policy = :file_wins
    configuration.logger = nil
    existing_entry = registry.upsert(key: 'job:a', cron: '* * * * *', enqueue: ->(**) {})
    expect(
      host.send(
        :resolve_register_conflict,
        key: 'job:a',
        cron: '* * * * *',
        enqueue: ->(**) {},
        existing_definition: { source: 'file' },
        existing_entry:
      )
    ).to eq(existing_entry)
  end

  it 'swallows rollback logging when no logger is configured' do
    configuration.logger = nil
    noisy_host = Class.new do
      include Kaal::RegisterConflictSupport

      attr_reader :configuration

      def initialize(configuration)
        @configuration = configuration
      end

      def rollback_registered_definition(*)
        raise 'rollback boom'
      end
    end.new(configuration)

    expect do
      noisy_host.send(:with_registered_definition_rollback, 'job:a', nil) { raise 'primary boom' }
    end.to raise_error(RuntimeError, 'primary boom')
  end
end
