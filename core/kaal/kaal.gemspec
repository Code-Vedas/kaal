# frozen_string_literal: true

version = File.read(File.expand_path('lib/kaal/version.rb', __dir__))
              .match(/VERSION\s*=\s*['"]([^'"]+)['"]/)[1]

Gem::Specification.new do |spec|
  spec.name        = 'kaal'
  spec.version     = version
  spec.authors = ['Nitesh Purohit', 'Codevedas Inc.']
  spec.email = ['nitesh.purohit.it@gmail.com', 'team@codevedas.com']
  spec.summary       = 'Distributed cron scheduler for Ruby.'
  spec.description   = <<-DESC
    Kaal is a distributed cron scheduler for Ruby that safely executes scheduled tasks across multiple nodes.
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
  spec.metadata['rubygems_uri'] = 'https://rubygems.org/gems/kaal'
  spec.metadata['rubygems_mfa_required'] = 'true'
  spec.bindir = 'exe'
  spec.executables = ['kaal']
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir['{config,exe,lib}/**/*', 'LICENSE', 'Rakefile', 'README.md']
  end

  spec.add_dependency 'fugit', '~> 1.8'
  spec.add_dependency 'i18n', '~> 1.14'
  spec.add_dependency 'thor', '~> 1.3'
  spec.add_dependency 'tzinfo', '~> 2.0'
  spec.required_ruby_version = '>= 3.2'
end
