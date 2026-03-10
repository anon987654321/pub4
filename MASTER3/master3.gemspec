# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name    = "master3"
  s.version = "3.0.0"
  s.summary = "Constitutional governance for an autonomous coding agent"
  s.authors = ["dev"]
  s.files   = Dir["lib/**/*.rb", "exe/*", "data/**/*", "*.yml"]
  s.executables = ["master3"]
  s.require_paths = ["lib"]
  s.ruby_version = ">= 3.3.0"

  s.add_dependency "ruby_llm",       "~> 1.3"
  s.add_dependency "tty-prompt",     "~> 0.23"
  s.add_dependency "tty-reader",     "~> 0.9"
  s.add_dependency "tty-spinner",    "~> 0.9"
  s.add_dependency "tty-markdown",   "~> 0.7"
  s.add_dependency "tty-table",      "~> 0.12"
  s.add_dependency "tty-screen",     "~> 0.8"
  s.add_dependency "tty-box",        "~> 0.7"
  s.add_dependency "tty-command",    "~> 0.10"
  s.add_dependency "tty-tree",       "~> 0.4"
  s.add_dependency "tty-config",     "~> 0.6"
  s.add_dependency "tty-logger",     "~> 0.6"
  s.add_dependency "tty-progressbar","~> 0.18"
  s.add_dependency "pastel",         "~> 0.8"
  s.add_dependency "rouge",          "~> 4.4"
  s.add_dependency "diffy",          "~> 3.4"
  s.add_dependency "zeitwerk",       "~> 2.7"
end
