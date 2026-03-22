# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
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

require 'kaal/sinatra'
require 'sequel'
require 'tmpdir'
require 'fileutils'
require 'time'
require 'yaml'

Dir[File.expand_path('support/**/*.rb', __dir__)].each { |file| require file }
Dir[File.expand_path('e2e/support/**/*.rb', __dir__)].each { |file| require file }

RSpec.configure do |config|
  config.example_status_persistence_file_path = '.rspec_status'
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.around do |example|
    Kaal.reset_configuration!
    Kaal.reset_registry!
    Kaal.reset_coordinator!
    example.run
    Kaal.reset_configuration!
    Kaal.reset_registry!
    Kaal.reset_coordinator!
  end
end
