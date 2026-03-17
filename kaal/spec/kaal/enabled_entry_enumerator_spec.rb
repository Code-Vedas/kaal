# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'

RSpec.describe Kaal::EnabledEntryEnumerator do
  subject(:enumerator) do
    described_class.new(
      configuration: configuration,
      registry: registry,
      definition_registry_provider: definition_registry_provider
    )
  end

  let(:logger) { instance_spy(Logger) }
  let(:configuration) do
    Kaal::Configuration.new.tap do |config|
      config.logger = logger
    end
  end
  let(:registry) { Kaal::Registry.new }
  let(:definition_registry_provider) { -> { definition_registry } }
  let(:definition_registry) { instance_double(Kaal::Definition::Registry) }

  describe '#each' do
    it 'falls back to in-memory registry when definition registry is nil' do
      registry.add(key: 'job:registry', cron: '* * * * *', enqueue: ->(fire_time:, idempotency_key:) {})
      definition_registry_provider = -> {}

      yielded = described_class.new(
        configuration: configuration,
        registry: registry,
        definition_registry_provider: definition_registry_provider
      ).each.map(&:key)

      expect(yielded).to eq(['job:registry'])
      expect(logger).not_to have_received(:warn).with(/Failed to iterate enabled definitions/)
    end

    it 'iterates over enabled definitions and yields resolved entries' do
      registry.add(key: 'job:one', cron: '* * * * *', enqueue: ->(fire_time:, idempotency_key:) {})
      definitions = [{ key: 'job:one', cron: '*/5 * * * *', enabled: true }]
      allow(definition_registry).to receive_messages(enabled_definitions: definitions, all_definitions: definitions)

      yielded = enumerator.each.to_a

      expect(yielded.size).to eq(1)
      expect(yielded.first.key).to eq('job:one')
      expect(yielded.first.cron).to eq('*/5 * * * *')
    end

    it 'warns and skips definitions with missing callback registrations' do
      definitions = [{ key: 'job:missing', cron: '* * * * *', enabled: true }]
      allow(definition_registry).to receive_messages(enabled_definitions: definitions, all_definitions: definitions)

      yielded = enumerator.each.to_a

      expect(yielded).to eq([])
      expect(logger).to have_received(:warn).with(/No enqueue callback registered for definition 'job:missing'/)
    end

    it 'skips missing callback definitions without warning when logger is nil' do
      configuration.logger = nil
      definitions = [{ key: 'job:missing-no-logger', cron: '* * * * *', enabled: true }]
      allow(definition_registry).to receive_messages(enabled_definitions: definitions, all_definitions: definitions)

      yielded = nil
      expect { yielded = enumerator.each.to_a }.not_to raise_error
      expect(yielded).to eq([])
    end

    it 'warns and skips definitions when callback exists but enqueue is nil' do
      callback_entry = instance_double(Kaal::Registry::Entry, enqueue: nil)
      allow(registry).to receive(:find).with('job:nil-enqueue').and_return(callback_entry)
      definitions = [{ key: 'job:nil-enqueue', cron: '* * * * *', enabled: true }]
      allow(definition_registry).to receive_messages(enabled_definitions: definitions, all_definitions: definitions)

      yielded = enumerator.each.to_a

      expect(yielded).to eq([])
      expect(logger).to have_received(:warn).with(/No enqueue callback registered for definition 'job:nil-enqueue'/)
    end

    it 'yields nothing when persisted definitions exist but all are disabled' do
      registry.add(key: 'job:disabled', cron: '* * * * *', enqueue: ->(fire_time:, idempotency_key:) {})
      all_definitions = [{ key: 'job:disabled', cron: '* * * * *', enabled: false }]
      allow(definition_registry).to receive_messages(enabled_definitions: [], all_definitions: all_definitions)

      yielded = enumerator.each.map(&:key)

      expect(yielded).to eq([])
    end

    it 'falls back to in-memory registry iteration when no persisted definitions exist' do
      registry.add(key: 'job:fallback', cron: '* * * * *', enqueue: ->(fire_time:, idempotency_key:) {})
      allow(definition_registry).to receive_messages(enabled_definitions: [], all_definitions: [])

      yielded = enumerator.each.map(&:key)

      expect(yielded).to eq(['job:fallback'])
    end

    it 'falls back to in-memory registry iteration when definition iteration fails' do
      registry.add(key: 'job:fallback', cron: '* * * * *', enqueue: ->(fire_time:, idempotency_key:) {})
      allow(definition_registry).to receive(:enabled_definitions).and_raise(StandardError, 'boom')

      yielded = enumerator.each.map(&:key)

      expect(yielded).to eq(['job:fallback'])
      expect(logger).to have_received(:warn).with(/Failed to iterate enabled definitions: boom/)
    end

    it 'falls back to in-memory registry iteration when definition iteration fails and logger is nil' do
      configuration.logger = nil
      registry.add(key: 'job:fallback', cron: '* * * * *', enqueue: ->(fire_time:, idempotency_key:) {})
      allow(definition_registry).to receive(:enabled_definitions).and_raise(StandardError, 'boom')

      yielded = nil
      expect { yielded = enumerator.each.map(&:key) }.not_to raise_error
      expect(yielded).to eq(['job:fallback'])
    end
  end
end
