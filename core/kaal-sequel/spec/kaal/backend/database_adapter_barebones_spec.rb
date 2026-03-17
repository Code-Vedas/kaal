# frozen_string_literal: true

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
