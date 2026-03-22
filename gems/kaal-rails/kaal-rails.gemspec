# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
version = File.read(File.expand_path('lib/kaal/rails/version.rb', __dir__))
              .match(/VERSION\s*=\s*['"]([^'"]+)['"]/)[1]

Gem::Specification.new do |spec|
  spec.name        = 'kaal-rails'
  spec.version     = version
  spec.authors = ['Nitesh Purohit', 'Codevedas Inc.']
  spec.email = ['nitesh.purohit.it@gmail.com', 'team@codevedas.com']
  spec.summary       = 'Kaal-Rails provides seamless integration of Kaal with Ruby on Rails'
  spec.description   = <<-DESC
    Kaal-Rails is a Ruby gem that provides seamless integration of Kaal with Ruby on Rails, allowing you to easily schedule and manage cron jobs in a distributed environment using ActiveRecord models. With Kaal-Rails, you can define your cron jobs as ActiveRecord models, and Kaal will handle the scheduling and execution of those jobs across multiple instances of your Rails application. This makes it easy to build scalable and reliable background job processing systems in your Rails applications.
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
  spec.metadata['rubygems_uri'] = 'https://rubygems.org/gems/kaal-rails'
  spec.metadata['rubygems_mfa_required'] = 'true'
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir['{bin,config,exe,lib}/**/*', 'LICENSE', 'Rakefile', 'README.md']
  end
  spec.add_dependency 'kaal', "= #{version}"
  spec.add_dependency 'kaal-activerecord', "= #{version}"
  spec.add_dependency 'rails', '>= 7.1', '< 9.0'
  spec.add_dependency 'rails-i18n', '>= 7.0'
  spec.required_ruby_version = '>= 3.2'
end
