# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'
require 'open3'

RSpec.describe Kaal::ActiveRecord do
  it 'raises an actionable load error when active record is unavailable' do
    allow(described_class).to receive(:require).with('active_record').and_raise(LoadError, 'cannot load such file -- active_record')

    expect { described_class.require_activerecord! }.to raise_error(
      LoadError,
      /Add `gem 'activerecord'` to your Gemfile to use Active Record-backed Kaal SQL support\./
    )
  end

  it 'exposes active record migration templates through the internal surface' do
    require 'kaal/internal/active_record/migration_templates'

    expect(Kaal::Internal::ActiveRecord::MigrationTemplates.for_backend(:sqlite).keys).to eq(
      %w[001_create_kaal_dispatches.rb 002_create_kaal_locks.rb 003_create_kaal_definitions.rb 004_create_kaal_delayed_jobs.rb]
    )
    expect(Kaal::Internal::ActiveRecord::MigrationTemplates.for_backend(:postgres).keys).to eq(
      %w[001_create_kaal_dispatches.rb 002_create_kaal_definitions.rb 003_create_kaal_delayed_jobs.rb]
    )
    expect(Kaal::Internal::ActiveRecord::MigrationTemplates.for_backend(:mysql).keys).to eq(
      %w[001_create_kaal_dispatches.rb 002_create_kaal_definitions.rb 003_create_kaal_delayed_jobs.rb]
    )
  end

  it 'does not eagerly load active record internals on require "kaal"' do
    output, status = Open3.capture2e(
      'bundle', 'exec', RbConfig.ruby,
      "-I#{File.expand_path('../../lib', __dir__)}",
      '-e', 'require "kaal"; puts defined?(Kaal::Internal::ActiveRecord::BaseRecord).inspect'
    )

    expect(status.success?).to be(true), output
    expect(output.strip).to eq('nil')
  end
end
