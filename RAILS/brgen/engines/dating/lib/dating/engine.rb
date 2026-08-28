# frozen_string_literal: true

require "shared/vertical_engine"

module Dating
  # brgen's dating vertical as a mountable engine. The boot shape — autoload
  # paths, db/migrate, view and asset paths — is Shared::VerticalEngine, which is
  # the recipe in brgen/ENGINES.md; that file also carries the two gotchas
  # (require:, top-level mount) that live outside this class.
  class Engine < ::Rails::Engine
    isolate_namespace Dating
    include Shared::VerticalEngine
  end
end
