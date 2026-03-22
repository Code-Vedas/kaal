# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'

RSpec.describe 'Kaal::VERSION' do
  it 'matches the gem version string' do
    expect(Kaal::VERSION).to eq('0.2.1')
  end
end
