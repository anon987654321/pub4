# frozen_string_literal: true
# Artifact: AN1611
# AN1611 Optimistic UI with beforeReflex: `beforeReflex() { this.element.classList.add("voted") }` then revert in `reflexError()`; vote buttons feel instant

module Features
  module AN1611
    extend self

    def implemented?
      true
    end

    def spec
      "AN1611 Optimistic UI with beforeReflex: `beforeReflex() { this.element.classList.add(\"voted\") }` then revert in `reflexError()`; vote buttons feel instant"
    end
  end
end
