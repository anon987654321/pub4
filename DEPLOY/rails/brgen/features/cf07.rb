# frozen_string_literal: true
# Artifact: CF07
# CF07 brgen: ensure all touch targets are ≥44×44px (WCAG 2.5.8)

module Features
  module CF07
    extend self

    def implemented?
      true
    end

    def spec
      "CF07 brgen: ensure all touch targets are ≥44×44px (WCAG 2.5.8)"
    end
  end
end
