# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Kaal::Sinatra, integration: :sqlite do
  include SinatraIntegrationHelpers

  it 'integrates a classic Sinatra app through the sqlite backend' do
    run_dummy_app(:classic, backend: 'sqlite', app_class_name: 'Sinatra::Application') do |app_root, _env, lines|
      database_path = KaalSinatraDummyAppSupport.database_path(app_root)
      database = Sequel.sqlite(database_path)

      expect(lines).to eq(['200', 'Kaal::Backend::DatabaseAdapter', 'true'])
      expect(database[:kaal_definitions].count).to eq(1)
      expect(database[:kaal_dispatches].count).to eq(2)
      expect(database[:kaal_locks].count).to eq(2)
      expect(File.read(KaalSinatraDummyAppSupport.job_log_path(app_root))).not_to be_empty
    ensure
      database&.disconnect
    end
  end

  it 'integrates a modular Sinatra app through the sqlite backend' do
    run_dummy_app(:modular, backend: 'sqlite', app_class_name: 'ModularDummyApp') do |app_root, _env, lines|
      database_path = KaalSinatraDummyAppSupport.database_path(app_root)
      database = Sequel.sqlite(database_path)

      expect(lines).to eq(['200', 'Kaal::Backend::DatabaseAdapter', 'true'])
      expect(database[:kaal_definitions].count).to eq(1)
      expect(database[:kaal_dispatches].count).to eq(2)
      expect(database[:kaal_locks].count).to eq(2)
      expect(File.read(KaalSinatraDummyAppSupport.job_log_path(app_root))).not_to be_empty
    ensure
      database&.disconnect
    end
  end
end
