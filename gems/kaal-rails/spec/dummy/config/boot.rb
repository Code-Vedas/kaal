# frozen_string_literal: true

# Set up gems listed in the Gemfile.
ENV['BUNDLE_GEMFILE'] = ENV.fetch('KAAL_RAILS_BUNDLE_GEMFILE')

require 'bundler/setup' if File.exist?(ENV['BUNDLE_GEMFILE'])
$LOAD_PATH.unshift(ENV.fetch('KAAL_RAILS_LIB_PATH', File.expand_path('../../../lib', __dir__)))
