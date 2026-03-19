# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
RSpec.describe Kaal::Sequel do
  it 'has a version number' do
    expect(Kaal::Sequel::VERSION).to eq('0.2.1')
  end

  it 'connects through the persistence wrapper and exposes migration templates' do
    database = Kaal::Persistence::Database.new('sqlite:/')

    expect(database.connection).to be_a(Sequel::Database)
    expect(Kaal::Persistence::MigrationTemplates.for_backend(:sqlite).keys).to eq(
      %w[001_create_kaal_dispatches.rb 002_create_kaal_locks.rb 003_create_kaal_definitions.rb]
    )
    expect(Kaal::Persistence::MigrationTemplates.for_backend(:postgres).keys).to eq(
      %w[001_create_kaal_dispatches.rb 002_create_kaal_definitions.rb]
    )
    expect(Kaal::Persistence::MigrationTemplates.for_backend(:memory)).to eq({})
  end

  it 'covers pure definition persistence helper branches' do
    now = Time.utc(2026, 1, 1, 0, 0, 0)

    expect(
      Kaal::Definition::PersistenceHelpers.disabled_at_for({ disabled_at: now, enabled: false }, false, now + 60)
    ).to eq(now)
    expect(Kaal::Definition::PersistenceHelpers.parse_metadata('')).to eq({})
  end
end
