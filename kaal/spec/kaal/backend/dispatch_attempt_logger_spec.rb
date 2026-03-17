# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'

RSpec.describe Kaal::Backend::DispatchAttemptLogger do
  subject(:attempt_logger) do
    described_class.new(
      configuration: configuration,
      dispatch_registry_provider: dispatch_registry_provider,
      logger: logger,
      node_id_provider: node_id_provider
    )
  end

  let(:configuration) { Kaal::Configuration.new }
  let(:logger) { instance_spy(Logger) }
  let(:registry) { instance_double(Kaal::Dispatch::MemoryEngine) }
  let(:dispatch_registry_provider) { -> { registry } }
  let(:node_id_provider) { -> { 'node-1' } }

  before do
    allow(registry).to receive(:log_dispatch)
  end

  it 'returns early when dispatch logging is disabled' do
    configuration.enable_log_dispatch_registry = false

    attempt_logger.call('kaal:dispatch:daily_job:1609459200')

    expect(registry).not_to have_received(:log_dispatch)
  end

  it 'returns early when the adapter has no dispatch registry' do
    configuration.enable_log_dispatch_registry = true
    registryless_logger = described_class.new(
      configuration: configuration,
      dispatch_registry_provider: -> {},
      logger: logger,
      node_id_provider: node_id_provider
    )

    registryless_logger.call('kaal:dispatch:daily_job:1609459200')

    expect(logger).not_to have_received(:error)
  end

  it 'logs dispatch attempts through the registry' do
    configuration.enable_log_dispatch_registry = true

    attempt_logger.call('kaal:dispatch:daily_job:1609459200')

    expect(registry).to have_received(:log_dispatch).with('daily_job', Time.at(1_609_459_200), 'node-1', 'dispatched')
  end

  it 'logs failures through the injected logger' do
    configuration.enable_log_dispatch_registry = true
    allow(registry).to receive(:log_dispatch).and_raise(StandardError, 'registry failure')

    attempt_logger.call('kaal:dispatch:daily_job:1609459200')

    expect(logger).to have_received(:error).with('Failed to log dispatch for kaal:dispatch:daily_job:1609459200: registry failure')
  end

  it 'falls back to the configuration logger when no logger is injected' do
    configuration.enable_log_dispatch_registry = true
    configuration.logger = logger
    allow(registry).to receive(:log_dispatch).and_raise(StandardError, 'registry failure')
    fallback_logger = described_class.new(
      configuration: configuration,
      dispatch_registry_provider: dispatch_registry_provider,
      node_id_provider: node_id_provider
    )

    fallback_logger.call('kaal:dispatch:daily_job:1609459200')

    expect(logger).to have_received(:error).with('Failed to log dispatch for kaal:dispatch:daily_job:1609459200: registry failure')
  end

  it 'does not raise when logging fails and no logger is available' do
    configuration.enable_log_dispatch_registry = true
    allow(registry).to receive(:log_dispatch).and_raise(StandardError, 'registry failure')
    nil_logger = described_class.new(
      configuration: configuration,
      dispatch_registry_provider: dispatch_registry_provider,
      node_id_provider: node_id_provider
    )

    expect { nil_logger.call('kaal:dispatch:daily_job:1609459200') }.not_to raise_error
  end
end
