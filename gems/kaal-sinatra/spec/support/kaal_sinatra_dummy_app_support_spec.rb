# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'

RSpec.describe KaalSinatraDummyAppSupport do
  it 'requires a test-like database name before resetting postgres databases' do
    expect do
      described_class.reset_database!('postgres://localhost:5432/kaal_production')
    end.to raise_error(ArgumentError, /Refusing to reset non-test database/)
  end

  it 'requires a test-like database name before resetting mysql databases' do
    expect do
      described_class.reset_database!('mysql2://localhost:3306/kaal_production')
    end.to raise_error(ArgumentError, /Refusing to reset non-test database/)
  end

  it 'allows test-like database names to continue to the backend reset path' do
    allow(described_class).to receive(:reset_postgres_database!)

    described_class.reset_database!('postgres://localhost:5432/kaal_test_auto')

    expect(described_class).to have_received(:reset_postgres_database!).once
  end

  it 'allows explicit override for non-test database names' do
    allow(described_class).to receive(:reset_mysql_database!)

    described_class.reset_database!(
      'mysql2://localhost:3306/kaal_production',
      env: { 'KAAL_ALLOW_DATABASE_RESET' => '1' }
    )

    expect(described_class).to have_received(:reset_mysql_database!).once
  end

  it 'identifies accepted test database names' do
    expect(described_class.test_database_name?('kaal_test_auto')).to be(true)
    expect(described_class.test_database_name?('kaal-spec-db')).to be(true)
    expect(described_class.test_database_name?('kaal_production')).to be(false)
  end
end
