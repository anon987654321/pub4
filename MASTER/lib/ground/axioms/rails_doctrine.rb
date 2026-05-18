# frozen_string_literal: true

module Master
  module Ground
  module Axioms
  module RailsDoctrine
    # The nine pillars — rubyonrails.org/doctrine (DHH)
    # Cite these when justifying architectural decisions, not just Rails apps.
    PILLARS = {
      happiness:       "Optimize for programmer happiness",
      convention:      "Convention over Configuration",
      omakase:         "The menu is omakase",
      no_one_paradigm: "No one paradigm",
      beautiful_code:  "Exalt beautiful code",
      sharp_knives:    "Provide sharp knives",
      integrated:      "Value integrated systems",
      progress:        "Progress over stability",
      big_tent:        "Push up a big tent"
    }.freeze

    # Solid Trifecta — database-backed adapters; eliminates Redis/PaaS dependency.
    # Doctrine basis: :integrated — "Value integrated systems"
    SOLID_TRIFECTA = %w[solid_queue solid_cache solid_cable].freeze

    def self.cite(pillar, rationale)
      name = PILLARS.fetch(pillar) { pillar.to_s }
      "[Rails Doctrine — #{name}] #{rationale}"
    end
  end
  end
  end
end
