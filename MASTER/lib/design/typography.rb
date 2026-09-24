# frozen_string_literal: true

module Master
  module Design
    # Contextual typography profiles. The values are constraints for a surface,
    # not universal aesthetic verdicts.
    module Typography
      CONTEXTUAL = {
        editorial: { text_wrap: "pretty", numerals: "oldstyle-nums", tables: "tabular-nums", punctuation: "hanging", justification: "hyphens_only" },
        legal: { text_wrap: "pretty", numerals: "oldstyle-nums", tables: "tabular-nums", punctuation: "hanging", justification: "hyphens_only" },
        social: { text_wrap: "pretty", numerals: "oldstyle-nums", tables: "tabular-nums", punctuation: "hanging", justification: "never" },
        marketplace: { text_wrap: "pretty", numerals: "lining-nums", tables: "tabular-nums", punctuation: "hanging", justification: "never" },
        terminal: { text_wrap: "stable", numerals: "lining-nums", tables: "tabular-nums", punctuation: "none", justification: "never" },
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

      def self.profile(name, root: Master::ROOT)
        name = name.to_sym
        typography = Master::Design::Thresholds.load(root:).fetch("typography", {})
        line_height = typography.fetch("line_height", {})
        access = typography.fetch("accessibility", {})
        measure = case name
                  when :social then Master::Design::Thresholds.worn_profile("feed", root:)["measure_max_ch"].to_f
                  when :marketplace then Master::Design::Thresholds.worn_profile("catalog", root:)["measure_max_ch"].to_f
                  when :terminal then 80.0
                  else Master::Design::Thresholds.measure_ideal_ch(root:).to_f
                  end
        CONTEXTUAL.fetch(name).merge(
          measure: measure,
          body_leading: line_height.fetch("body_preferred", 1.5).to_f,
          heading_leading: line_height.fetch("heading_preferred", 1.25).to_f,
          minimum_body_px: access.fetch("body_min_px", 16).to_i,
        )
      end

      def self.for_surface(path:, purpose: nil, root: Master::ROOT)
        route = path.to_s.split("?").first
        return profile(ROUTE_PROFILES.fetch(route), root:) if ROUTE_PROFILES.key?(route)

        text = [route, purpose].compact.join(" ").downcase
        return profile(:legal, root:) if text.match?(/privacy|terms|cookie|legal/)
        return profile(:marketplace, root:) if text.match?(/market|item|deal|order|cart|shop/)
        return profile(:terminal, root:) if text.match?(/terminal|console|cli|shell|bsdports/)
        return profile(:social, root:)
      end

      def self.brief(path:, purpose: nil, root: Master::ROOT)
        values = for_surface(path:, purpose:, root:)
        "measure=#{format("%g", values[:measure])}ch body_leading=#{values[:body_leading]} heading_leading=#{values[:heading_leading]} "           "min_body=#{values[:minimum_body_px]}px wrap=#{values[:text_wrap]} numerals=#{values[:numerals]} "           "tables=#{values[:tables]} punctuation=#{values[:punctuation]} justification=#{values[:justification]}"
      end
    end
  end
end
