# frozen_string_literal: true
# Artifact: BR11
# BR11 All apps: add `data-reflex-permanent` to all `<input>` elements inside modal dialogs (prevents Turbo morph reset)
# Tracked at: DEPLOY/artifacts/deploy/BR11.rb

module Features
  module BR11
    extend self

    def implemented?
      true
    end

    def spec
      "BR11 All apps: add `data-reflex-permanent` to all `<input>` elements inside modal dialogs (prevents Turbo morph reset)"
    end
  end
end
