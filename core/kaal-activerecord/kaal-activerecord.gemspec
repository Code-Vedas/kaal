# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
version = File.read(File.expand_path('lib/kaal/active_record/version.rb', __dir__))
              .match(/VERSION\s*=\s*['"]([^'"]+)['"]/)[1]

Gem::Specification.new do |spec|
  spec.name        = 'kaal-activerecord'
  spec.version     = version
  spec.authors = ['Nitesh Purohit', 'Codevedas Inc.']
  spec.email = ['nitesh.purohit.it@gmail.com', 'team@codevedas.com']
  spec.summary       = 'ActiveRecord integration for Kaal, a distributed cron scheduler for Ruby.'
  spec.description   = <<-DESC
    Kaal-ActiveRecord provides seamless integration of Kaal with ActiveRecord, allowing you to use ActiveRecord models for scheduling and managing cron jobs in a distributed environment.
  DESC
  spec.homepage      = 'https://github.com/Code-Vedas/kaal'
  spec.license       = 'MIT'
  spec.metadata['bug_tracker_uri'] = 'https://github.com/Code-Vedas/kaal/issues'
  spec.metadata['changelog_uri'] = 'https://github.com/Code-Vedas/kaal/blob/main/CHANGELOG.md'
  spec.metadata['documentation_uri'] = 'https://kaal.codevedas.com'
  spec.metadata['homepage_uri'] = 'https://github.com/Code-Vedas/kaal'
  spec.metadata['source_code_uri'] = 'https://github.com/Code-Vedas/kaal.git'
  spec.metadata['funding_uri'] = 'https://github.com/sponsors/Code-Vedas'
  spec.metadata['support_uri'] = 'https://kaal.codevedas.com/support'
  spec.metadata['rubygems_uri'] = 'https://rubygems.org/gems/kaal-activerecord'
  spec.metadata['rubygems_mfa_required'] = 'true'
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir['{config,exe,lib}/**/*', 'LICENSE', 'Rakefile', 'README.md']
  end
  spec.add_dependency 'kaal', "~> #{version}"
  spec.add_dependency 'rails', '>= 7.1', '< 9.0'
  spec.add_dependency 'rails-i18n', '>= 7.0'
  spec.required_ruby_version = '>= 3.2'
end
