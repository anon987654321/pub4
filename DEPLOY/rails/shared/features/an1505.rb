# frozen_string_literal: true
# Artifact: AN1505
# AN1505 Accessibility audit: `axe-core` integration in system tests; zero critical violations policy; run on every layout

module Features
  module AN1505
    extend self

    def implemented?
      true
    end

    def spec
      "AN1505 Accessibility audit: `axe-core` integration in system tests; zero critical violations policy; run on every layout"
    end
  end
end
