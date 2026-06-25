# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name    = "master"
  spec.version = "0.1.0"
  spec.authors = ["dev"]
  spec.summary = "Constitutional AI agent"

  spec.files         = Dir["lib/**/*.rb", "kernel/**/*.rb", "bin/*", "data/**/*", "LETTER_TO_AUTHOR.md"]
  spec.require_paths = ["lib"]
  spec.bindir        = "bin"
  spec.executables   = ["cli", "master-kernel", "status"]

  spec.required_ruby_version = ">= 3.3"

  spec.add_dependency "zeitwerk",   "~> 2.7"
  spec.add_dependency "ruby_llm",   "~> 1.3"
  spec.add_dependency "tty-prompt", "~> 0.23"
  spec.add_dependency "pastel",     "~> 0.8"
  spec.add_dependency "rouge",      "~> 4.4"
  spec.add_dependency "diffy",      "~> 3.4"
end
