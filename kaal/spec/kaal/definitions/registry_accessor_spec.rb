# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'

RSpec.describe Kaal::Definitions::RegistryAccessor do
  subject(:accessor) do
    described_class.new(configuration: configuration, fallback_registry_provider: fallback_registry_provider)
  end

  let(:configuration) { Kaal::Configuration.new }
  let(:fallback_registry) { instance_double(Kaal::Definition::MemoryEngine) }
  let(:fallback_registry_provider) { -> { fallback_registry } }

  it 'returns the backend definition registry when available' do
    backend_registry = instance_double(Kaal::Definition::Registry)
    backend = instance_double(Kaal::Backend::MemoryAdapter, definition_registry: backend_registry)
    configuration.backend = backend

    expect(accessor.call).to be(backend_registry)
  end

  it 'falls back when the backend has no definition registry' do
    configuration.backend = Object.new

    expect(accessor.call).to be(fallback_registry)
  end

  it 'falls back when the backend raises NoMethodError for definition_registry' do
    backend = instance_double(Kaal::Backend::MemoryAdapter)
    configuration.backend = backend
    allow(backend).to receive(:definition_registry).and_raise(NoMethodError)

    expect(accessor.call).to be(fallback_registry)
  end
end
