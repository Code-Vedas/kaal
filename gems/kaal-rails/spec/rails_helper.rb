# frozen_string_literal: true

require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
original_database_url = ENV.delete('DATABASE_URL')
require_relative 'dummy/config/environment'
abort('The Rails environment is running in production mode!') if Rails.env.production?
require 'rspec/rails'
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end
ENV['DATABASE_URL'] = original_database_url if original_database_url
RSpec.configure do |config|
  config.fixture_paths = [
    Rails.root.join('spec/fixtures')
  ]
  config.use_transactional_fixtures = true
  config.filter_rails_from_backtrace!
end
