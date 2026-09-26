# frozen_string_literal: true

require "yaml"

Gem::Specification.new do |spec|
  spec.name    = "master"
  # soul.yml is the one version this repo actually bumps (soul propose ->
  # soul approve). A second hardcoded number here drifted to "0.1.0" against
  # soul's 2.8.0 because nothing kept them in sync; read it instead of
  # copying it.
  spec.version = YAML.safe_load_file(File.join(__dir__, "data", "soul.yml")).fetch("version")
  spec.authors = ["dev"]
  spec.summary = "Constitutional AI agent"

  # kernel/ and LETTER_TO_AUTHOR.md do not exist in this tree; Dir[] on a
  # missing path silently contributes nothing; and no Rakefile or CI task
  # actually builds or installs this gemspec, but a package built from a
  # correct list is worth more than one that quietly ships fewer files than
  # it claims to.
  spec.files         = Dir["lib/**/*.rb", "bin/*", "data/**/*", "plugins/**/*"]
  spec.require_paths = ["lib"]
  spec.bindir        = "bin"
  spec.executables   = ["cli", "master-kernel", "status"]

  spec.required_ruby_version = ">= 4.0"

  spec.add_dependency "zeitwerk",   "~> 2.7"
  spec.add_dependency "ruby_llm",   "~> 2.0"
  spec.add_dependency "ruby_llm-mcp", "~> 1.0"
  spec.add_dependency "tty-prompt", "~> 0.23"
  spec.add_dependency "pastel",     "~> 0.8"
  spec.add_dependency "diffy",      "~> 3.4"
  spec.add_dependency "ferrum",     "~> 0.15"
end
