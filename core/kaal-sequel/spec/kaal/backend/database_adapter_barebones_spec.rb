# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'

RSpec.describe Kaal::Backend::DatabaseAdapter do
  it 'loads the sequel-backed adapters and registries explicitly' do
    require 'kaal/sequel'

    expect(defined?(Kaal::Dispatch::DatabaseEngine)).to eq('constant')
    expect(defined?(Kaal::Definition::DatabaseEngine)).to eq('constant')
    expect(described_class.name).to eq('Kaal::Backend::DatabaseAdapter')
    expect(defined?(Kaal::Backend::PostgresAdapter)).to eq('constant')
    expect(defined?(Kaal::Backend::MySQLAdapter)).to eq('constant')
    expect(defined?(Kaal::Backend::SQLiteAdapter)).to eq('constant')
  end
end
