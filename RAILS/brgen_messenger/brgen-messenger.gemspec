# frozen_string_literal: true

require_relative "lib/brgen_messenger/version"

Gem::Specification.new do |spec|
  spec.name = "brgen-messenger"
  spec.version = BrgenMessenger::VERSION
  spec.authors = ["pub4"]
  spec.summary = "brgen messaging vertical"
  spec.files = Dir["{app,config,db,lib}/**/*"].select { |f| File.file?(f) }
  spec.require_paths = ["lib"]
  spec.add_dependency "rails", ">= 8.0"
  spec.add_dependency "pub4-shared"
end
