# frozen_string_literal: true
# Artifact: BR15
# BR15 All apps: replace `cable_ready.broadcast` with `cable_ready.broadcast_to` (scoped to model) for cache invalidation
# Tracked at: DEPLOY/artifacts/deploy/BR15.rb

module Features
  module BR15
    extend self

    def implemented?
      true
    end

    def spec
      "BR15 All apps: replace `cable_ready.broadcast` with `cable_ready.broadcast_to` (scoped to model) for cache invalidation"
    end
  end
end
