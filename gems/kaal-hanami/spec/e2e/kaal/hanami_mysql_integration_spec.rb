# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'

RSpec.describe Kaal::Hanami, integration: :mysql do
  include HanamiIntegrationHelpers

  it 'integrates a Hanami app through the mysql backend' do
    skip 'DATABASE_URL not set' if ENV['DATABASE_URL'].to_s.empty?

    run_dummy_app(
      backend: 'mysql',
      env: { 'DATABASE_URL' => ENV.fetch('DATABASE_URL') }
    ) do |app_root, env, lines|
      database = Sequel.connect(env.fetch('DATABASE_URL'))

      expect(lines).to eq(['200', 'Kaal::Backend::MySQLAdapter', 'true'])
      expect(database[:kaal_definitions].count).to eq(1)
      expect(database[:kaal_dispatches].count).to eq(2)
      expect(database.tables).not_to include(:kaal_locks)
      expect(File.read(KaalHanamiDummyAppSupport.job_log_path(app_root))).not_to be_empty
    ensure
      database&.disconnect
    end
  end
end
