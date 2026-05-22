# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'

RSpec.describe Kaal::Sequel do
  it 'raises an actionable load error when sequel is unavailable' do
    allow(described_class).to receive(:require).with('sequel').and_raise(LoadError, 'cannot load such file -- sequel')

    expect { described_class.require_sequel! }.to raise_error(
      LoadError,
      /Add `gem 'sequel'` to your Gemfile to use Sequel-backed Kaal SQL support\./
    )
  end

  it 'exposes migration templates for sql backends' do
    expect(Kaal::Persistence::MigrationTemplates.for_backend(:sqlite).keys).to eq(
      %w[001_create_kaal_dispatches.rb 002_create_kaal_locks.rb 003_create_kaal_definitions.rb 004_create_kaal_delayed_jobs.rb]
    )
    expect(Kaal::Persistence::MigrationTemplates.for_backend(:postgres).keys).to eq(
      %w[001_create_kaal_dispatches.rb 002_create_kaal_definitions.rb 003_create_kaal_delayed_jobs.rb]
    )
    expect(Kaal::Persistence::MigrationTemplates.for_backend(:mysql).keys).to eq(
      %w[001_create_kaal_dispatches.rb 002_create_kaal_definitions.rb 003_create_kaal_delayed_jobs.rb]
    )
  end
end
