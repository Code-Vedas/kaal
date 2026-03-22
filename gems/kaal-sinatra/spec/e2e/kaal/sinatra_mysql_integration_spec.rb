# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Kaal::Sinatra, integration: :mysql do
  include SinatraIntegrationHelpers

  it 'integrates a classic Sinatra app through the mysql backend' do
    skip 'DATABASE_URL not set' if ENV['DATABASE_URL'].to_s.empty?

    run_dummy_app(
      :classic,
      backend: 'mysql',
      app_class_name: 'Sinatra::Application',
      env: { 'DATABASE_URL' => ENV.fetch('DATABASE_URL') }
    ) do |app_root, env, lines|
      database = Sequel.connect(env.fetch('DATABASE_URL'))

      expect(lines).to eq(['200', 'Kaal::Backend::MySQLAdapter', 'true'])
      expect(database[:kaal_definitions].count).to eq(1)
      expect(database[:kaal_dispatches].count).to eq(2)
      expect(database.tables).not_to include(:kaal_locks)
      expect(File.read(KaalSinatraDummyAppSupport.job_log_path(app_root))).not_to be_empty
    ensure
      database&.disconnect
    end
  end

  it 'integrates a modular Sinatra app through the mysql backend' do
    skip 'DATABASE_URL not set' if ENV['DATABASE_URL'].to_s.empty?

    run_dummy_app(
      :modular,
      backend: 'mysql',
      app_class_name: 'ModularDummyApp',
      env: { 'DATABASE_URL' => ENV.fetch('DATABASE_URL') }
    ) do |app_root, env, lines|
      database = Sequel.connect(env.fetch('DATABASE_URL'))

      expect(lines).to eq(['200', 'Kaal::Backend::MySQLAdapter', 'true'])
      expect(database[:kaal_definitions].count).to eq(1)
      expect(database[:kaal_dispatches].count).to eq(2)
      expect(database.tables).not_to include(:kaal_locks)
      expect(File.read(KaalSinatraDummyAppSupport.job_log_path(app_root))).not_to be_empty
    ensure
      database&.disconnect
    end
  end
end
