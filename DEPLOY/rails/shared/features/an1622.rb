# frozen_string_literal: true
# Artifact: AN1622
# AN1622 stimulus-animated-number for counters: `data-controller="stimulus-animated-number"` on vote counts, follower counts, impact stats; numbers count up on first view

module Features
  module AN1622
    extend self

    def implemented?
      true
    end

    def spec
      "AN1622 stimulus-animated-number for counters: `data-controller=\"stimulus-animated-number\"` on vote counts, follower counts, impact stats; numbers count up on first view"
    end
  end
end
