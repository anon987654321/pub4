# frozen_string_literal: true
# Artifact: BR05
# BR05 amber outfit builder: add `data-reflex="change->Outfit#reorder"` on sortable list (PATCH /outfits/:id/reorder)
# Tracked at: DEPLOY/artifacts/deploy/BR05.rb

module Features
  module BR05
    extend self

    def implemented?
      true
    end

    def spec
      "BR05 amber outfit builder: add `data-reflex=\"change->Outfit#reorder\"` on sortable list (PATCH /outfits/:id/reorder)"
    end
  end
end
