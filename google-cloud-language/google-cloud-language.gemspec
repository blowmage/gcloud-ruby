# -*- ruby -*-
# encoding: utf-8

require File.expand_path("lib/google/cloud/language/version", __dir__)

Gem::Specification.new do |gem|
  gem.name          = "google-cloud-language"
  gem.version       = Google::Cloud::Language::VERSION

  gem.authors       = ["Google LLC"]
  gem.email         = "googleapis-packages@google.com"
  gem.description   = "google-cloud-language is the official library for Google Cloud Language API."
  gem.summary       = "API Client library for Google Cloud Language API"
  gem.homepage      = "https://github.com/googleapis/googleapis"
  gem.license       = "Apache-2.0"

  gem.platform      = Gem::Platform::RUBY

  gem.files         = `git ls-files -- lib/*`.split("\n") +
                      ["README.md", "LICENSE", ".yardopts"]
  gem.require_paths = ["lib"]

  gem.required_ruby_version = ">= 2.0.0"

  gem.add_dependency "gapic-common", "~> 0.0.0"
  gem.add_dependency "google-cloud-core", "~> 1.4"

  gem.add_development_dependency "google-style", "~> 0.3"
  gem.add_development_dependency "minitest", "~> 5.10"
  gem.add_development_dependency "redcarpet", "~> 3.0"
  gem.add_development_dependency "simplecov", "~> 0.9"
  gem.add_development_dependency "yard", "~> 0.9"
end
