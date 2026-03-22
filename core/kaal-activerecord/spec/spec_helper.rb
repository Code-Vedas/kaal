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

require 'rails'
require 'kaal/active_record'
require 'tmpdir'
require 'fileutils'

Dir[File.expand_path('support/**/*.rb', __dir__)].each { |file| require file }
Dir[File.expand_path('e2e/support/**/*.rb', __dir__)].each { |file| require file }

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
  config.shared_context_metadata_behavior = :apply_to_host_groups

  config.before do
    Kaal::ActiveRecord::BaseRecord.remove_connection
  rescue StandardError
    nil
  end
end
