# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'

RSpec.describe Kaal::Backend::DispatchRegistryAccessor do
  subject(:accessor) { described_class.new(configuration: configuration) }

  let(:configuration) { Kaal::Configuration.new }

  describe '#dispatched?' do
    it 'returns false when the backend does not support a dispatch registry' do
      configuration.backend = Object.new

      expect(accessor.dispatched?('job', Time.current)).to be(false)
    end

    it 'returns false when the dispatch registry is nil' do
      backend = instance_double(Kaal::Backend::MemoryAdapter, dispatch_registry: nil)
      configuration.backend = backend

      expect(accessor.dispatched?('job', Time.current)).to be(false)
    end

    it 'delegates to the dispatch registry when available' do
      fire_time = Time.current
      registry = instance_double(Kaal::Dispatch::MemoryEngine)
      backend = instance_double(Kaal::Backend::MemoryAdapter, dispatch_registry: registry)
      configuration.backend = backend
      allow(registry).to receive(:dispatched?).with('job', fire_time).and_return(true)

      expect(accessor.dispatched?('job', fire_time)).to be(true)
    end

    it 'returns false and logs when registry lookup raises' do
      logger = instance_spy(Logger)
      registry = instance_double(Kaal::Dispatch::MemoryEngine)
      backend = instance_double(Kaal::Backend::MemoryAdapter, dispatch_registry: registry)
      configuration.backend = backend
      configuration.logger = logger
      allow(registry).to receive(:dispatched?).and_raise(StandardError, 'db error')

      expect(accessor.dispatched?('job', Time.current)).to be(false)
      expect(logger).to have_received(:warn).with(/Error checking dispatch status/)
    end
  end

  describe '#registry' do
    it 'returns the dispatch registry when available' do
      registry = instance_double(Kaal::Dispatch::MemoryEngine)
      backend = instance_double(Kaal::Backend::MemoryAdapter, dispatch_registry: registry)
      configuration.backend = backend

      expect(accessor.registry).to be(registry)
    end

    it 'returns nil and logs when the backend raises' do
      logger = instance_spy(Logger)
      backend = instance_double(Kaal::Backend::MemoryAdapter)
      configuration.backend = backend
      configuration.logger = logger
      allow(backend).to receive(:dispatch_registry).and_raise(StandardError, 'backend error')

      expect(accessor.registry).to be_nil
      expect(logger).to have_received(:warn).with(/Error accessing dispatch registry/)
    end
  end
end
