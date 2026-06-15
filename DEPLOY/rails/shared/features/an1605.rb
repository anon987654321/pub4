# frozen_string_literal: true
# Artifact: AN1605
# AN1605 Declarative reflex bindings: `data-reflex="click->Post#vote"` — zero JS; use on vote buttons, follow buttons, reaction buttons across all apps

module Features
  module AN1605
    extend self

    def implemented?
      true
    end

    def spec
      "AN1605 Declarative reflex bindings: `data-reflex=\"click->Post#vote\"` — zero JS; use on vote buttons, follow buttons, reaction buttons across all apps"
    end
  end
end
