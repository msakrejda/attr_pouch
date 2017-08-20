require File.expand_path('../lib/attr_pouch/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Maciek Sakrejda"]
  gem.email         = ["m.sakrejda@gmail.com"]
  gem.description   = %q{Schema-less attribute storage}
  gem.summary       = %q{Sequel plugin for schema-less attribute storage}
  gem.homepage      = "https://github.com/uhoh-itsmaciek/attr_pouch"

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "attr_pouch"
  gem.require_paths = ["lib"]
  gem.version       = AttrPouch::VERSION
  gem.license       = "MIT"

  gem.add_development_dependency "rspec", '~> 3.0'
  gem.add_development_dependency "pg", '~> 0.18.3'
  gem.add_development_dependency "sequel", '~> 4.46'
end
