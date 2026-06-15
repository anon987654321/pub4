# frozen_string_literal: true
# Artifact: BR08
# BR08 bsdports search: add `data-reflex="input->Search#live"` for live search with debounce
# Tracked at: DEPLOY/artifacts/deploy/BR08.rb

module Features
  module BR08
    extend self

    def implemented?
      true
    end

    def spec
      "BR08 bsdports search: add `data-reflex=\"input->Search#live\"` for live search with debounce"
    end
  end
end
