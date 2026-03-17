# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'

RSpec.describe Kaal::Definitions::RegistrationService do
  subject(:service) do
    described_class.new(configuration: configuration, definition_registry: definition_registry, registry: registry)
  end

  let(:configuration) { Kaal::Configuration.new }
  let(:definition_registry) { instance_double(Kaal::Definition::Registry) }
  let(:registry) { instance_double(Kaal::Registry) }

  it 'registers a new code-defined job' do
    enqueue = ->(fire_time:, idempotency_key:) { [fire_time, idempotency_key] }
    allow(definition_registry).to receive(:find_definition).with('job').and_return(nil)
    allow(definition_registry).to receive(:upsert_definition)
    allow(registry).to receive(:find).with('job').and_return(nil)
    allow(registry).to receive(:add).with(key: 'job', cron: '* * * * *', enqueue: enqueue).and_return(:entry)

    result = service.call(key: 'job', cron: '* * * * *', enqueue: enqueue)

    expect(result).to eq(:entry)
    expect(definition_registry).to have_received(:upsert_definition).with(
      key: 'job',
      cron: '* * * * *',
      enabled: true,
      source: 'code',
      metadata: {}
    )
  end

  it 'returns the existing entry when file_wins applies' do
    enqueue = ->(fire_time:, idempotency_key:) { [fire_time, idempotency_key] }
    existing_entry = instance_double(Kaal::Registry::Entry)
    existing_definition = { source: 'file' }
    configuration.scheduler_conflict_policy = :file_wins
    allow(definition_registry).to receive(:find_definition).with('job').and_return(existing_definition)
    allow(registry).to receive(:find).with('job').and_return(existing_entry)
    allow(configuration).to receive(:logger).and_return(instance_spy(Logger))

    expect(service.call(key: 'job', cron: '* * * * *', enqueue: enqueue)).to be(existing_entry)
  end

  it 'rolls back persisted definitions when registry add fails' do
    enqueue = ->(fire_time:, idempotency_key:) { [fire_time, idempotency_key] }
    allow(definition_registry).to receive(:find_definition).with('job').and_return(nil)
    allow(definition_registry).to receive(:upsert_definition)
    allow(definition_registry).to receive(:remove_definition)
    allow(registry).to receive(:find).with('job').and_return(nil)
    allow(registry).to receive(:add).and_raise(StandardError, 'registry failure')
    allow(registry).to receive(:registered?).with('job').and_return(false)

    expect { service.call(key: 'job', cron: '* * * * *', enqueue: enqueue) }.to raise_error(StandardError, 'registry failure')
    expect(definition_registry).to have_received(:remove_definition).with('job')
  end

  it 'logs rollback failures without swallowing the original error' do
    logger = instance_spy(Logger)
    enqueue = ->(fire_time:, idempotency_key:) { [fire_time, idempotency_key] }
    configuration.logger = logger
    allow(definition_registry).to receive(:find_definition).with('job').and_return(nil)
    allow(definition_registry).to receive(:upsert_definition)
    allow(definition_registry).to receive(:remove_definition).and_raise(StandardError, 'rollback failure')
    allow(registry).to receive(:find).with('job').and_return(nil)
    allow(registry).to receive(:add).and_raise(StandardError, 'registry failure')
    allow(registry).to receive(:registered?).with('job').and_return(false)

    expect { service.call(key: 'job', cron: '* * * * *', enqueue: enqueue) }.to raise_error(StandardError, 'registry failure')
    expect(logger).to have_received(:error).with(/Failed to rollback persisted definition/)
  end
end
