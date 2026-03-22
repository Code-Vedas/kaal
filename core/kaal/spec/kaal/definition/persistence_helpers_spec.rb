# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'

RSpec.describe Kaal::Definition::PersistenceHelpers do
  it 'parses metadata and falls back on empty or invalid JSON' do
    expect(described_class.parse_metadata('')).to eq({})
    expect(described_class.parse_metadata('{"owner":"ops"}')).to eq(owner: 'ops')
    expect(described_class.parse_metadata('{')).to eq({})
  end
end
