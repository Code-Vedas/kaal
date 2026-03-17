# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Kaal do
  it 'configures and exposes convenience readers' do
    described_class.configure do |config|
      config.tick_interval = 10
      config.namespace = 'test'
    end

    expect(described_class.tick_interval).to eq(10)
    expect(described_class.namespace).to eq('test')
  end

  it 'registers entries and persists definitions in the fallback registry' do
    entry = described_class.register(
      key: 'reports:daily',
      cron: '0 9 * * *',
      enqueue: ->(**) {}
    )

    expect(entry).to be_a(Kaal::Registry::Entry)
    expect(described_class.registered?(key: 'reports:daily')).to be(true)
    expect(described_class.registered.map(&:key)).to eq(['reports:daily'])
  end

  it 'delegates ticking to the coordinator' do
    coordinator = instance_double(Kaal::Coordinator, tick!: true)
    allow(described_class).to receive(:coordinator).and_return(coordinator)

    described_class.tick!

    expect(coordinator).to have_received(:tick!)
  end

  it 'resets top-level state and handles nil-safe registry and rollback branches' do
    described_class.instance_variable_set(:@definition_registry, nil)
    described_class.reset_registry!
    expect(described_class.registry).to be_a(Kaal::Registry)

    described_class.instance_variable_set(:@coordinator, nil)
    expect(described_class.reset_coordinator!).to be_a(Kaal::Coordinator)

    definition_registry = described_class.definition_registry
    definition_registry.upsert_definition(key: 'job:a', cron: '* * * * *', enabled: true, source: 'code', metadata: {})
    expect(described_class.registered.first.enqueue).to be_nil

    described_class.register(key: 'job:a', cron: '* * * * *', enqueue: ->(**) {})
    expect(described_class.send(:rollback_registered_definition, 'job:a', nil)).to be_nil
  end
end
