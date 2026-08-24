# frozen_string_literal: true

require_relative "lib/maps/version"

Gem::Specification.new do |spec|
  spec.name = "brgen-maps"
  spec.version = Maps::VERSION
  spec.authors = [ "pub4" ]
  spec.summary = "brgen maps vertical — mountable Rails engine"
  spec.files = Dir["{app,config,db,lib}/**/*"].select { |f| File.file?(f) }
  spec.require_paths = [ "lib" ]
  spec.add_dependency "rails", ">= 8.0"
  spec.add_dependency "pub4-shared"
end
