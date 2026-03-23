# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'

RSpec.describe Kaal::Hanami, integration: :sqlite do
  include HanamiIntegrationHelpers

  it 'integrates a Hanami app through the sqlite backend' do
    run_dummy_app(backend: 'sqlite') do |app_root, _env, lines|
      database_path = KaalHanamiDummyAppSupport.database_path(app_root)
      database = Sequel.sqlite(database_path)

      expect(lines).to eq(['200', 'Kaal::Backend::DatabaseAdapter', 'true'])
      expect(database[:kaal_definitions].count).to eq(1)
      expect(database[:kaal_dispatches].count).to eq(2)
      expect(database[:kaal_locks].count).to eq(2)
      expect(File.read(KaalHanamiDummyAppSupport.job_log_path(app_root))).not_to be_empty
    ensure
      database&.disconnect
    end
  end
end
