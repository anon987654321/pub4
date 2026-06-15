# frozen_string_literal: true
# Artifact: AN1616
# AN1616 scroll_into_view: `cable_ready.scroll_into_view(selector: "#new-message-#{id}", behavior: "smooth")` — auto-scroll to new chat message after CableReady append

module Features
  module AN1616
    extend self

    def implemented?
      true
    end

    def spec
      "AN1616 scroll_into_view: `cable_ready.scroll_into_view(selector: \"#new-message-\#{id}\", behavior: \"smooth\")` — auto-scroll to new chat message after CableReady append"
    end
  end
end
