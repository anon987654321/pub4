# frozen_string_literal: true
# Artifact: AN1613
# AN1613 Infinite scroll via append: `cable_ready.append(selector: "#feed", html: render_partial)` from Solid Queue job; no client JS beyond IntersectionObserver

module Features
  module AN1613
    extend self

    def implemented?
      true
    end

    def spec
      "AN1613 Infinite scroll via append: `cable_ready.append(selector: \"#feed\", html: render_partial)` from Solid Queue job; no client JS beyond IntersectionObserver"
    end
  end
end
