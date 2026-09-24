# frozen_string_literal: true

module Master
  module Design
    # Contextual typography profiles. The values are constraints for a surface,
    # not universal aesthetic verdicts.
    module Typography
      PROFILES = {
        editorial: {
          measure: 66,
          body_leading: 1.5,
          heading_leading: 1.25,
          minimum_body_px: 16,
          text_wrap: "pretty",
          numerals: "oldstyle-nums",
          tables: "tabular-nums",
          punctuation: "hanging",
          justification: "hyphens_only",
        },
        legal: {
          measure: 66,
          body_leading: 1.5,
          heading_leading: 1.25,
          minimum_body_px: 16,
          text_wrap: "pretty",
          numerals: "oldstyle-nums",
          tables: "tabular-nums",
          punctuation: "hanging",
          justification: "hyphens_only",
        },
        social: {
          measure: 50,
          body_leading: 1.5,
          heading_leading: 1.25,
          minimum_body_px: 16,
          text_wrap: "pretty",
          numerals: "oldstyle-nums",
          tables: "tabular-nums",
          punctuation: "hanging",
          justification: "never",
        },
        marketplace: {
          measure: 55,
          body_leading: 1.5,
          heading_leading: 1.25,
          minimum_body_px: 16,
          text_wrap: "pretty",
          numerals: "lining-nums",
          tables: "tabular-nums",
          punctuation: "hanging",
          justification: "never",
        },
        terminal: {
          measure: 80,
          body_leading: 1.4,
          heading_leading: 1.25,
          minimum_body_px: 14,
          text_wrap: "stable",
          numerals: "lining-nums",
          tables: "tabular-nums",
          punctuation: "none",
          justification: "never",
        },
      }.freeze

      ROUTE_PROFILES = {
        "/privacy" => :legal,
        "/terms" => :legal,
        "/cookies" => :legal,
        "/search" => :social,
        "/feed" => :social,
        "/posts" => :social,
        "/stories" => :social,
        "/messages" => :social,
        "/orders" => :marketplace,
        "/items/new" => :marketplace,
        "/registration/new" => :social,
        "/session/new" => :social,
      }.freeze

      def self.profile(name)
        PROFILES.fetch(name.to_sym)
      end

      def self.for_surface(path:, purpose: nil)
        route = path.to_s.split("?").first
        return profile(ROUTE_PROFILES.fetch(route)) if ROUTE_PROFILES.key?(route)

        text = [route, purpose].compact.join(" ").downcase
        return profile(:legal) if text.match?(/privacy|terms|cookie|legal/)
        return profile(:marketplace) if text.match?(/market|item|deal|order|cart|shop/)
        return profile(:terminal) if text.match?(/terminal|console|cli|shell|bsdports/)
        return profile(:social)
      end

      def self.brief(path:, purpose: nil)
        values = for_surface(path:, purpose:)
        "measure=#{values[:measure]}ch body_leading=#{values[:body_leading]} heading_leading=#{values[:heading_leading]} "           "min_body=#{values[:minimum_body_px]}px wrap=#{values[:text_wrap]} numerals=#{values[:numerals]} "           "tables=#{values[:tables]} punctuation=#{values[:punctuation]} justification=#{values[:justification]}"
      end
    end
  end
end
