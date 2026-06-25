# frozen_string_literal: true

module Master
  module Ground
    module Axioms
      module RailsDoctrine
        # Nine pillars from rubyonrails.org/doctrine (DHH); cite when justifying architectural decisions.
        PILLARS = {
          happiness: "Optimize for programmer happiness",
          convention: "Convention over Configuration",
          omakase: "The menu is omakase",
          no_one_paradigm: "No one paradigm",
          beautiful_code: "Exalt beautiful code",
          sharp_knives: "Provide sharp knives",
          integrated: "Value integrated systems",
          progress: "Progress over stability",
          big_tent: "Push up a big tent",
        }.freeze

        # Database-backed adapters; eliminates Redis/PaaS dependency. Doctrine: :integrated.
        SOLID_TRIFECTA = %w[solid_queue solid_cache solid_cable].freeze

        def self.cite(pillar, rationale)
          name = PILLARS.fetch(pillar) { pillar.to_s }
          "[Rails Doctrine — #{name}] #{rationale}"
        end
      end
    end
  end
end
