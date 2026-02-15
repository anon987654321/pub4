# frozen_string_literal: true

require_relative "lib/master"

Gem::Specification.new do |s|
  s.name          = "master2"
  s.version       = MASTER::VERSION
  s.summary       = "Constitutional AI Code Quality System"
  s.description   = "MASTER2 is a self-governing AI development partner with constitutional governance, adversarial council deliberation, four execution reasoning patterns, and self-improvement capabilities. OpenBSD-first."
  s.authors       = ["anon987654321"]
  s.homepage      = "https://github.com/anon987654321/pub4/tree/main/MASTER2"
  s.license       = "MIT"
  s.required_ruby_version = ">= 3.1.0"

  s.files         = Dir["lib/**/*.rb", "lib/views/**/*", "data/**/*", "bin/*", "completions/*", "sbin/*", "Gemfile", "README.md", "LICENSE"]
  s.bindir        = "bin"
  s.executables   = ["master"]

  # Runtime dependencies (from Gemfile)
  s.add_dependency "tty-reader", "~> 0.9"
  s.add_dependency "tty-spinner"
  s.add_dependency "tty-table"
  s.add_dependency "tty-box"
  s.add_dependency "tty-markdown"
  s.add_dependency "tty-prompt"
  s.add_dependency "tty-progressbar"
  s.add_dependency "tty-cursor"
  s.add_dependency "tty-tree"
  s.add_dependency "tty-pie"
  s.add_dependency "tty-pager"
  s.add_dependency "tty-link"
  s.add_dependency "tty-font"
  s.add_dependency "tty-editor"
  s.add_dependency "tty-command"
  s.add_dependency "tty-screen"
  s.add_dependency "tty-platform"
  s.add_dependency "tty-which"
  s.add_dependency "pastel"
  s.add_dependency "rouge"
  s.add_dependency "nokogiri", "~> 1.19"
  s.add_dependency "ruby_llm", "~> 1.11"
  s.add_dependency "stoplight", "~> 4.0"
  s.add_dependency "falcon", "~> 0.47"
  s.add_dependency "async-websocket"

  # Development dependencies
  s.add_development_dependency "minitest"
  s.add_development_dependency "rake"
  s.add_development_dependency "webmock"
end
