# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Kaal::Definition::PersistenceHelpers do
  it 'parses metadata and falls back on empty or invalid JSON' do
    expect(described_class.parse_metadata('')).to eq({})
    expect(described_class.parse_metadata('{"owner":"ops"}')).to eq(owner: 'ops')
    expect(described_class.parse_metadata('{')).to eq({})
  end
end
