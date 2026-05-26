# frozen_string_literal: true

module Master
  module Ground
  module BrutalistMinimalism
    NAME = "Brutalist-Minimalist Content-First".freeze
    PRIMARY_RULE = "If it does not improve readability, delete it.".freeze

    FORBIDDEN_EFFECTS = %w[
      shadows glows 3d_effects gradients animations transitions rounded_corners decorative_borders
    ].freeze

    FORBIDDEN_CSS = %w[
      box-shadow border-radius background-image transform filter
    ].freeze

    ALLOWED_CSS = %w[
      font-size font-weight margin padding line-height max-width display flex grid
    ].freeze

    SYSTEM_FONTS = {
      serif: "Georgia",
      sans_serif: "Arial/Helvetica"
    }.freeze

    METRICS = {
      css_bytes_max: 10_000,
      total_bytes_max: 10_000,
      line_length_min: 45,
      line_length_max: 75,
      line_length_ideal: 65,
      contrast_min: 4.5,
      load_time_2g_s: 2,
      lighthouse_target: 100
    }.freeze

    HTML_REQUIREMENTS = [
      "proper heading hierarchy",
      "meaningful alt text",
      "logical document flow",
      "accessible landmarks: main, nav, aside where appropriate",
      "screen-reader compatibility",
      "no styling-only divs",
      "no non-semantic markup",
      "no decorative elements"
    ].freeze

    ANTI_PATTERNS = [
      "visual metaphors",
      "smooth interactions",
      "aesthetic comfort",
      "decorative containers",
      "loading animations",
      "splash screens",
      "hero banners"
    ].freeze

    PROMPTS = {
      design_brief: "Create a brutally minimal website that prioritizes content over decoration.",
      development_constraint: "Use system fonts, single column layout, max 65 characters per line, no visual effects.",
      content_hierarchy: "Establish hierarchy through font size, weight, semantic headings, and spacing only.",
      performance_mandate: "HTML plus CSS under 10KB total; every byte must serve content delivery."
    }.freeze

    def self.brief
      <<~TEXT.strip
        #{NAME} policy:
        - #{PRIMARY_RULE}
        - black text on white background; no palette beyond black and white unless required for state.
        - system fonts only: serif=#{SYSTEM_FONTS[:serif]}, sans=#{SYSTEM_FONTS[:sans_serif]}; no web fonts.
        - single-column, content-first layout; 45-75ch lines, ideal #{METRICS[:line_length_ideal]}ch.
        - forbidden visual effects: #{FORBIDDEN_EFFECTS.join(', ')}.
        - forbidden CSS properties: #{FORBIDDEN_CSS.join(', ')}.
        - HTML must be semantic, accessible, heading-ordered, and screen-reader friendly.
        - JavaScript is forbidden unless critical; external resources are forbidden unless essential.
        - target: sub-#{METRICS[:load_time_2g_s]}s on 2G; HTML+CSS under #{METRICS[:total_bytes_max]}B;
          Lighthouse 100/100/100/100.
      TEXT
    end
  end
  end
end
