# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name    = "master"
  # Release version is canonical at the pub4 root; soul.yml remains the
  # constitutional revision and is intentionally independent.
  spec.version = File.read(File.join(__dir__, "..", "VERSION"), encoding: "UTF-8").strip
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
  spec.executables   = ["cli"]

  spec.required_ruby_version = ">= 3.3"

  spec.add_dependency "zeitwerk",   "~> 2.7"
  spec.add_dependency "ruby_llm", "~> 2.0"
  spec.add_dependency "mcp", "~> 1.6"
  spec.add_dependency "event_stream_parser", ">= 1.0"
  spec.add_dependency "faraday", ">= 2.0"
  spec.add_dependency "tty-prompt", "~> 0.23"
  spec.add_dependency "pastel",     "~> 0.8"
  spec.add_dependency "diffy",      "~> 3.4"
  spec.add_dependency "ferrum",     "~> 0.15"
end
