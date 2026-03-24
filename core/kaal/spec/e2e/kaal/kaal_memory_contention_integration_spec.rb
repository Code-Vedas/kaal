# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'

RSpec.describe Kaal, integration: :memory do
  it 'dispatches at most once per fire time under concurrent memory-backed ticks' do
    key = 'contention:memory'
    namespace = KaalIntegrationSupport.namespace('contention-memory')
    base_time = Time.utc(2026, 1, 1, 0, 0, 30)
    shared_backend = Kaal::Backend::MemoryAdapter.new

    result = KaalContentionSupport.run_threaded_contention(
      fixed_times: KaalContentionSupport.repeated_fire_times(base_time, iterations: 3),
      key: key,
      namespace: namespace,
      node_count: 4,
      backend_factory: ->(_) { shared_backend }
    )

    KaalContentionSupport.assert_single_dispatch_per_iteration!(result)

    expect(shared_backend.dispatch_registry.size).to eq(3)

    result.fetch(:iterations).each do |iteration|
      fire_time = iteration.fetch(:expected_fire_time)
      expect(shared_backend.dispatch_registry.find_dispatch(key, fire_time)).to include(status: 'dispatched')
    end
  end
end
