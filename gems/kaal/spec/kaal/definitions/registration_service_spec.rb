# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'

RSpec.describe Kaal::Definitions::RegistrationService do
  let(:logger_io) { StringIO.new }
  let(:configuration) { Kaal::Configuration.new.tap { |config| config.logger = Logger.new(logger_io) } }
  let(:definition_registry) { Kaal::Definition::MemoryEngine.new }
  let(:registry) { Kaal::Registry.new }
  let(:service) { described_class.new(configuration:, definition_registry:, registry:) }
  let(:callback) { ->(**) {} }

  it 'registers code-defined jobs and preserves persisted metadata' do
    definition_registry.upsert_definition(key: 'job:a', cron: '* * * * *', enabled: false, source: 'code', metadata: { owner: 'ops' })

    entry = service.call(key: 'job:a', cron: '*/5 * * * *', enqueue: callback)

    expect(entry).to be_a(Kaal::Registry::Entry)
    expect(definition_registry.find_definition('job:a')).to include(enabled: false, metadata: { owner: 'ops' })
  end

  it 'raises for duplicate code registrations' do
    registry.add(key: 'job:a', cron: '* * * * *', enqueue: callback)
    definition_registry.upsert_definition(key: 'job:a', cron: '* * * * *', enabled: true, source: 'code', metadata: {})

    expect { service.call(key: 'job:a', cron: '* * * * *', enqueue: callback) }.to raise_error(Kaal::RegistryError)
  end

  it 'handles file-defined conflicts for each scheduler policy' do
    registry.add(key: 'job:a', cron: '* * * * *', enqueue: callback)
    definition_registry.upsert_definition(key: 'job:a', cron: '* * * * *', enabled: true, source: 'file', metadata: { owner: 'ops' })

    configuration.scheduler_conflict_policy = :file_wins
    expect(service.call(key: 'job:a', cron: '* * * * *', enqueue: callback)).to eq(registry.find('job:a'))
    expect(logger_io.string).to include('scheduler_conflict_policy is :file_wins')

    configuration.scheduler_conflict_policy = :error
    expect { service.call(key: 'job:a', cron: '* * * * *', enqueue: callback) }.to raise_error(Kaal::RegistryError, /scheduler file/)

    configuration.scheduler_conflict_policy = :code_wins
    replacement = service.call(key: 'job:a', cron: '*/5 * * * *', enqueue: callback)
    expect(replacement.cron).to eq('*/5 * * * *')
    expect(definition_registry.find_definition('job:a')).to include(source: 'code')

    definition_registry.upsert_definition(key: 'job:a', cron: '* * * * *', enabled: true, source: 'file', metadata: {})
    configuration.scheduler_conflict_policy = :unknown
    expect { service.call(key: 'job:a', cron: '* * * * *', enqueue: callback) }.to raise_error(Kaal::SchedulerConfigError, /Unsupported/)
  end

  it 'rolls back persisted definitions when registry add fails' do
    broken_registry = Kaal::Registry.new
    allow(broken_registry).to receive(:add).and_raise(StandardError, 'boom')
    service = described_class.new(configuration:, definition_registry:, registry: broken_registry)

    expect { service.call(key: 'job:a', cron: '* * * * *', enqueue: callback) }.to raise_error(StandardError, 'boom')
    expect(definition_registry.find_definition('job:a')).to be_nil
  end

  it 'logs rollback failures from register conflict support' do
    service.define_singleton_method(:rollback_registered_definition) { |_key, _existing_definition| raise 'rollback boom' }

    expect do
      service.send(:with_registered_definition_rollback, 'job:a', {}) do
        raise StandardError, 'primary boom'
      end
    end.to raise_error(StandardError, 'primary boom')

    expect(logger_io.string).to include('Failed to rollback persisted definition for job:a: rollback boom')
  end

  it 'restores an existing persisted definition during rollback' do
    service.send(
      :rollback_registered_definition,
      'job:a',
      { key: 'job:a', cron: '*/5 * * * *', enabled: false, source: 'file', metadata: { owner: 'ops' } }
    )

    expect(definition_registry.find_definition('job:a')).to include(cron: '*/5 * * * *', source: 'file')
  end

  it 'keeps persisted definitions untouched when the registry still has the key' do
    registry.add(key: 'job:a', cron: '* * * * *', enqueue: callback)

    expect(service.send(:rollback_registered_definition, 'job:a', nil)).to be_nil
    expect(definition_registry.find_definition('job:a')).to be_nil
  end
end
