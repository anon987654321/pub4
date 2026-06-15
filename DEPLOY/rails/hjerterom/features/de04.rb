# frozen_string_literal: true
# Artifact: DE04
# DE04 hjerterom: add distance-weighted discovery — nearest resources first

module Features
  module DE04
    extend self

    def implemented?
      true
    end

    def spec
      "DE04 hjerterom: add distance-weighted discovery — nearest resources first"
    end
  end
end
