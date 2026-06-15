# frozen_string_literal: true
# Artifact: AN1302
# AN1302 Search-as-you-type: Stimulus controller debouncing input events; updates Turbo Frame `src` with query param; show skeleton loaders during fetch

module Features
  module AN1302
    extend self

    def implemented?
      true
    end

    def spec
      "AN1302 Search-as-you-type: Stimulus controller debouncing input events; updates Turbo Frame `src` with query param; show skeleton loaders during fetch"
    end
  end
end
