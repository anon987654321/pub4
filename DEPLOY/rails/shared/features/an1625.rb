# frozen_string_literal: true
# Artifact: AN1625
# AN1625 stimulus-character-counter on all textareas: `data-controller="stimulus-character-counter" data-stimulus-character-counter-max-value="280"` — visible limit indicator

module Features
  module AN1625
    extend self

    def implemented?
      true
    end

    def spec
      "AN1625 stimulus-character-counter on all textareas: `data-controller=\"stimulus-character-counter\" data-stimulus-character-counter-max-value=\"280\"` — visible limit indicator"
    end
  end
end
