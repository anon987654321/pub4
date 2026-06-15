# frozen_string_literal: true
# Artifact: BR07
# BR07 blognet article editor: add `data-reflex="blur->Article#auto_save"` on ActionText editor
# Tracked at: DEPLOY/artifacts/deploy/BR07.rb

module Features
  module BR07
    extend self

    def implemented?
      true
    end

    def spec
      "BR07 blognet article editor: add `data-reflex=\"blur->Article#auto_save\"` on ActionText editor"
    end
  end
end
