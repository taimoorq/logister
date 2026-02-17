require_relative 'lib/logister/version'

Gem::Specification.new do |spec|
  spec.name = 'logister-ruby'
  spec.version = Logister::VERSION
  spec.authors = ['Logister']
  spec.email = ['support@logister.org']

  spec.summary = 'Send Rails errors and metrics to logister.org'
  spec.description = 'Client gem for reporting errors and custom metrics from Ruby and Rails apps to logister.org'
  spec.homepage = 'https://logister.org'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.1.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/taimoorq/logister-ruby'

  spec.files = Dir.chdir(__dir__) do
    Dir.glob('lib/**/*') + ['README.md', 'logister-ruby.gemspec']
  end

  spec.require_paths = ['lib']

  spec.add_dependency 'activesupport', '>= 6.1'
  spec.add_development_dependency 'rake', '>= 13.0'
end
