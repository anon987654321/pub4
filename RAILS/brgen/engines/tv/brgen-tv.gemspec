# frozen_string_literal: true

require_relative "lib/tv/version"

Gem::Specification.new do |spec|
  spec.name = "brgen-tv"
  spec.version = Tv::VERSION
  spec.authors = [ "pub4" ]
  spec.summary = "brgen TV vertical — mountable Rails engine (video, live streams, shows)"
  spec.files = Dir["{app,config,db,lib}/**/*"].select { |f| File.file?(f) }
  spec.require_paths = [ "lib" ]
  spec.add_dependency "rails", ">= 8.0"
  # The vertical depends on the fleet-shared engine for User, auth, tenancy,
  # design system and the social concerns it mixes into its models.
  spec.add_dependency "pub4-shared"
end
