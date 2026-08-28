# frozen_string_literal: true

require "shared/vertical_engine"

module Maps
  # Maps surface as a mountable engine. Place stays a host model — restaurant
  # and store now point at it, so it has two consumers and is shared the same
  # way User is. This engine owns routes, controllers and views only, over the
  # boot shape in Shared::VerticalEngine.
  # See brgen/ENGINES.md (messenger-shaped extract).
  class Engine < ::Rails::Engine
    isolate_namespace Maps
    include Shared::VerticalEngine
  end
end
