# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'multish/version'

Gem::Specification.new do |spec|
  spec.name          = 'multish'
  spec.version       = Multish::VERSION
  spec.authors       = ['Tomasz Dąbrowski']
  spec.email         = ['t.dabrowski@rock-hard.eu']

  spec.summary       = 'Run multiple commands in one terminal, side by side'
  spec.description   = 'Run multiple commands in one terminal, side by side'
  spec.homepage      = 'http://github.com/dabroz/multish'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler', '~> 2.2'
  spec.add_development_dependency 'rake', '~> 12.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'rubocop', '~> 1.0'

  spec.add_runtime_dependency 'curses'
end
