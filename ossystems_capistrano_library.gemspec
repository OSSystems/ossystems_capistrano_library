# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'ossystems_capistrano_library/version'

Gem::Specification.new do |gem|
  gem.name          = "ossystems_capistrano_library"
  gem.version       = OssystemsCapistranoLibrary::VERSION
  gem.authors       = ["Lucas Dutra Nunes"]
  gem.email         = ["ldnunes@ossystems.com.br"]
  gem.description   = %q{Capistrano deploy recipes for O.S. System Rails projects}
  gem.summary       = %q{Customizable Capistrano deploy recipes for O.S. System Rails projects.}
  gem.homepage      = "http://www.ossystems.com.br/"

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.add_dependency('rvm-capistrano', '~> 1.5.0')
end
