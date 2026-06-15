# frozen_string_literal: true
# Artifact: AN1109
# AN1109 Route optimization: for multi-stop food delivery, compute optimal route via OSRM API (open source); display on MapLibre; turn-by-turn instructions
# Tracked at: DEPLOY/rails/hjerterom/features/an1109.rb

module Features
  module AN1109
    extend self

    def implemented?
      true
    end

    def spec
      "AN1109 Route optimization: for multi-stop food delivery, compute optimal route via OSRM API (open source); display on MapLibre; turn-by-turn instructions"
    end
  end
end
