# coding: utf-8

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'hussh/version'

Gem::Specification.new do |spec|
  spec.name        = 'hussh'
  spec.version     = Hussh::VERSION
  spec.author      = 'Misha Gorodnitzky'
  spec.email       = 'misaka@pobox.com'
  spec.homepage    = 'http://github.com/moneyadviceservice/hussh'
  spec.summary     = 'Session-recording library for Net::SSH to make testing easy'
  spec.description = spec.summary
  spec.license     = 'New BSD'

  spec.files            = `git ls-files -z lib`.split("\x0")
  spec.test_files       = `git ls-files -z spec`.split("\x0")
  spec.require_paths    = ['lib']
  spec.extra_rdoc_files = ['README.rdoc']

  spec.add_development_dependency 'bundler', '~> 1.7'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rdoc', '~> 4.2'
  spec.add_development_dependency 'rspec', '~> 3.2'
  spec.add_development_dependency 'rspec-mocks', '~> 3.2'
  spec.add_development_dependency 'fakefs', '~> 0.6'
  spec.add_development_dependency 'pry', '~> 0.10'
  spec.add_development_dependency 'guard-rspec', '~> 4.5'
  spec.add_development_dependency 'net-ssh', '~> 2.9'
  spec.add_development_dependency 'codeclimate-test-reporter'
end
