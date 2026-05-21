# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'

RSpec.describe Kaal::Backend::SQLite do
  it 'loads the explicit sql backends from require "kaal"' do
    expect(defined?(Kaal::Dispatch::DatabaseEngine)).to eq('constant')
    expect(defined?(Kaal::Definition::DatabaseEngine)).to eq('constant')
    expect(described_class.name).to eq('Kaal::Backend::SQLite')
    expect(defined?(Kaal::Backend::Postgres)).to eq('constant')
    expect(defined?(Kaal::Backend::MySQL)).to eq('constant')
  end
end
