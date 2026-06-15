# frozen_string_literal: true
# Artifact: AN1301
# AN1301 Global search: `/search?q=` across all models in app; ranked by type priority and recency; Turbo Frame instant results as user types (debounced 200ms)

module Features
  module AN1301
    extend self

    def implemented?
      true
    end

    def spec
      "AN1301 Global search: `/search?q=` across all models in app; ranked by type priority and recency; Turbo Frame instant results as user types (debounced 200ms)"
    end
  end
end
