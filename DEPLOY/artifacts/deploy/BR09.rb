# frozen_string_literal: true
# Artifact: BR09
# BR09 baibl verse navigation: add `data-reflex="keydown.arrowDown->Verse#next"` for keyboard bible reading
# Tracked at: DEPLOY/artifacts/deploy/BR09.rb

module Features
  module BR09
    extend self

    def implemented?
      true
    end

    def spec
      "BR09 baibl verse navigation: add `data-reflex=\"keydown.arrowDown->Verse#next\"` for keyboard bible reading"
    end
  end
end
