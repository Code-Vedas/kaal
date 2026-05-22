# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'
Kaal::ActiveRecord.require_activerecord!
require 'kaal/internal/active_record'

RSpec.describe Kaal::Internal::ActiveRecord::MySQLBackend do
  let(:dispatch_registry) { instance_double(Kaal::Internal::ActiveRecord::DispatchRegistry) }
  let(:definition_registry) { instance_double(Kaal::Internal::ActiveRecord::DefinitionRegistry) }

  before do
    allow(Kaal::Internal::ActiveRecord::ConnectionSupport).to receive(:configure!)
  end

  it 'acquires, releases, and normalizes lock names' do
    backend = described_class.new(nil, dispatch_registry:, definition_registry:)
    allow(backend).to receive(:scalar).and_return(1, 1)
    allow(backend).to receive(:log_dispatch_attempt)

    expect(backend.acquire('short-key', 10)).to be(true)
    expect(backend.release('short-key')).to be(true)
    expect(described_class.send(:normalize_lock_name, 'x' * 80)).to match(/\A.{47}:.{16}\z/)
    expect(backend.dispatch_registry).to eq(dispatch_registry)
    expect(backend.definition_registry).to eq(definition_registry)
  end

  it 'wraps adapter errors and covers unsuccessful acquisition' do
    backend = described_class.new(nil)
    allow(backend).to receive(:scalar).and_raise('boom')
    expect { backend.acquire('key', 10) }.to raise_error(Kaal::Backend::LockAdapterError, /MySQL acquire failed/)
    expect { backend.release('key') }.to raise_error(Kaal::Backend::LockAdapterError, /MySQL release failed/)

    backend = described_class.new(nil)
    allow(backend).to receive(:scalar).and_return(0)
    allow(backend).to receive(:log_dispatch_attempt)
    expect(backend.acquire('key', 10)).to be(false)
  end

  it 'builds a skip-locked delayed store when mysql supports it' do
    delayed_store = instance_double(Kaal::Internal::ActiveRecord::DelayedJobRegistry)
    allow(Kaal::Internal::ActiveRecord::DelayedJobRegistry).to receive(:new).and_return(delayed_store)

    backend = described_class.new(
      nil,
      dispatch_registry:,
      definition_registry:,
      use_skip_locked: true
    )

    expect(backend.dispatch_registry).to eq(dispatch_registry)
    expect(backend.definition_registry).to eq(definition_registry)
    expect(backend.delayed_store).to eq(delayed_store)
    expect(Kaal::Internal::ActiveRecord::DelayedJobRegistry).to have_received(:new).with(use_skip_locked: true)
  end

  it 'falls back when mysql skip locked support is disabled' do
    delayed_store = instance_double(Kaal::Internal::ActiveRecord::DelayedJobRegistry)
    allow(Kaal::Internal::ActiveRecord::DelayedJobRegistry).to receive(:new).and_return(delayed_store)

    backend = described_class.new(nil, use_skip_locked: false)

    expect(backend.delayed_store).to eq(delayed_store)
    expect(Kaal::Internal::ActiveRecord::DelayedJobRegistry).to have_received(:new).with(use_skip_locked: false)
  end

  it 'detects skip-locked support from mysql version strings' do
    backend = described_class.new(nil)
    allow(backend).to receive(:scalar).with('SELECT VERSION() AS version').and_return('8.0.36', '5.7.44')

    expect(backend.send(:supports_skip_locked?)).to be(true)
    backend.instance_variable_set(:@use_skip_locked, described_class::UNSET_SKIP_LOCKED_SUPPORT)
    expect(backend.send(:supports_skip_locked?)).to be(false)
  end
end
