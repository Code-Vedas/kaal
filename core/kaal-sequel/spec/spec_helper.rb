# frozen_string_literal: true

unless ENV['NO_COVERAGE'] == '1'
  require 'simplecov'

  SimpleCov.start do
    enable_coverage :branch
    track_files 'lib/**/*.rb'
    add_filter '/spec/'
    minimum_coverage line: 100, branch: 100
  end
end

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'kaal/sequel'
require 'tmpdir'
require 'fileutils'
require 'time'

Dir[File.expand_path('support/**/*.rb', __dir__)].each { |file| require file }

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
