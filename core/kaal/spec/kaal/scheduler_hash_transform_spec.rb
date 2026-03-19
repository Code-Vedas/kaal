# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'

RSpec.describe Kaal::SchedulerHashTransform do
  it 'delegates stringify and symbolize helpers through the mixin' do
    host = Class.new do
      include Kaal::SchedulerHashTransform

      def call(value)
        [stringify_keys(value), symbolize_keys_deep(value)]
      end
    end.new

    stringified, symbolized = host.call(a: { b: 1 })
    expect(stringified).to eq('a' => { 'b' => 1 })
    expect(symbolized).to eq(a: { b: 1 })
  end
end
