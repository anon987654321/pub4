# frozen_string_literal: true
# Artifact: AN1606
# AN1606 Form auto-save: `data-reflex="change->Draft#save" data-reflex-serialize-form="true"` on each draft textarea; auto-saves to DB on every keystroke (debounced server-side)

module Features
  module AN1606
    extend self

    def implemented?
      true
    end

    def spec
      "AN1606 Form auto-save: `data-reflex=\"change->Draft#save\" data-reflex-serialize-form=\"true\"` on each draft textarea; auto-saves to DB on every keystroke (debounced server-side)"
    end
  end
end
