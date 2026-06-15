# frozen_string_literal: true
# Artifact: AN1617
# AN1617 stimulus-sortable for outfit/playlist ordering: `data-controller="stimulus-sortable"` + `data-sortable-url-value="/outfits/:id/reorder"` — drag to reorder, PATCH persists order

module Features
  module AN1617
    extend self

    def implemented?
      true
    end

    def spec
      "AN1617 stimulus-sortable for outfit/playlist ordering: `data-controller=\"stimulus-sortable\"` + `data-sortable-url-value=\"/outfits/:id/reorder\"` — drag to reorder, PATCH persists order"
    end
  end
end
