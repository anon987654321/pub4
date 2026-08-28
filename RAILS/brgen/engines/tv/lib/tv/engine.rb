# frozen_string_literal: true

require "shared/vertical_engine"

module Tv
  # brgen's TV vertical, extracted from the host app 2026-08-02 as the pilot for
  # the vertical-as-engine split. Its boot shape is Shared::VerticalEngine, the
  # one place the six verticals now share — including the `<<` on the frozen
  # Rails 8.1 path arrays that this pilot cost a boot to find. See ENGINES.md.
  class Engine < ::Rails::Engine
    isolate_namespace Tv
    include Shared::VerticalEngine
  end
end
