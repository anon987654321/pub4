# frozen_string_literal: true

# law/brand.rb — the Bergen brand-system laws, one Law.define per law.
#
# Source of every law here is a MEASURED failure or a MEASURED decision from
# building the Sommerseth Eiendom and Alfa Bergen sites (RAILS/__other),
# calibrated against bob.no's production design system. The doctrine lives in
# docs/visual/bergen_brand_systems.md; these laws are the line-level teeth
# /fix walks when it repairs that tree.
#
# 2026-10-28: both source sites were retired and RAILS/__other deleted. The
# laws stay — they are design decisions, and decisions outlive their first
# tree. SIGNAL_COLOR_NAMING, PAPER_NOT_PURE_WHITE and PARAMETRIC_MARK_ONLY are
# scoped (their `path`) to brand-export trees, because the four
# RAILS apps declare --accent, #ffffff and long icon paths as their own
# measured, operator-owned identity (see RAILS/__shared dialect tokens) and
# these three laws must not read that scheme as drift. The remaining three
# walk RAILS/** universally: measured there, zero findings.

Law.define(:SIGNAL_COLOR_NAMING) do
  path %r{/mrdamascy/}
  source "Bergen brand systems - one signal colour per identity (bob.no calibration)"
  detect { |line| line.match?(/--(accent|accent-color|secondary-color|highlight-color)\s*:/) }
  fix "Name the single signal colour --signal; no accent/secondary/highlight twins."
  bad  "--accent: #E07A00;"
  good "--signal: #C97E1E;"
end

Law.define(:PAPER_NOT_PURE_WHITE) do
  path %r{/mrdamascy/}
  source "Bergen brand systems - paper tones, not #FFF (storefront_art matte-paper rule)"
  detect { |line| line.match?(/background(-color)?:\s*(#fff\b|#ffffff\b|white)\s*;/i) }
  fix "Paint page scopes with the paper token, never pure white."
  bad  "background: #FFFFFF;"
  good "background: var(--paper);"
end

Law.define(:PARAMETRIC_MARK_ONLY) do
  path %r{/mrdamascy/}
  source "Bergen-snittet v1 - marks derive from a parametric source, never hand-drawn"
  detect { |line| line.match?(/d="M[\d\s.,A-Za-z-]{80,}"/) }
  fix "Compose marks from the parametric constants (src/lib/marks.ts + scripts/gen-marks.mjs); short paths, named parts."
  bad  '<path d="M4 35.5 L22.5 13.5 L41 35.5 M7 43.5 H41 M34.5 9.5 m-5.5 0 a5.5 5.5 0 1 0 11 0 a5.5 5.5 0 0 0 -11 0" />'
  good "d={SOMMERSETH.roof}"
end

Law.define(:WORDMASK_OBSERVES_UNCLIPPED) do
  source "Framer Motion + IntersectionObserver - a fully clipped element never intersects"
  # Measured: whileInView on the masked word span (y: 112% inside its own
  # overflow:hidden mask) reports intersection area 0 forever — the headline
  # stayed invisible. Observe the outer, unclipped wrapper; drive the inner
  # spans with animate.
  detect { |line| line.include?("whileInView") && line.match?(/y:\s*'\d+%'/) }
  fix "useInView on the outer wrapper, animate on the inner word spans."
  bad  "<motion.span className=\"wr-word\" initial={{ y: '112%' }} whileInView={{ y: '0%' }}>"
  good "const inView = useInView(outerRef); <motion.span animate={inView ? { y: '0%' } : { y: '112%' }}>"
end

Law.define(:CURSOR_NONE_REQUIRES_CURSOR) do
  source "Bergen brand systems - hiding the cursor is a promise to replace it"
  detect { |line| line.match?(/cursor:\s*none/) }
  fix "Avoid hiding the native cursor unless a replacement is rendered and gated by pointer:fine and prefers-reduced-motion; review the full component."
  bad  ".page { cursor: none; }"
  good ".page { cursor: auto; }"
end

Law.define(:NORWEGIAN_COPY_BOKMAL) do
  source "Bergen brand systems - user-facing copy in Norwegian bokmål (snl.no orthography)"
  detect { |line| line.match?(/(?:placeholder|title|description|alt)="[^"]*\b(?:the|and|with|your)\b[^"]*"/i) }
  fix "Write user-facing strings in Norwegian bokmål; å/ø/æ, snl.no orthography."
  bad  'alt="Red cabin by the fjord at dusk"'
  good 'alt="Rødt trehus ved fjorden i kveldslys"'
end

# DIALECT_CONTRAST_PARITY reads tokens.yml alone: each dialect's light and dark modes keep the
# same contrast per colour role. The values stay operator-owned; the Law reports drift and the
# operator floors of 2026-11-06 (muted 4.5:1, body text 7:1).
require "yaml"
require_relative "../checks/support/rendered_design"

module Law
  module DialectContrast
    ROLES = { "text" => %w[text], "muted" => %w[muted text_secondary], "border" => %w[border],
              "accent" => %w[accent] }.freeze
    NAMES = ROLES.keys.freeze
    FLOOR = { "text" => 7.0, "muted" => 4.5 }.freeze
    DRIFT = %w[muted border].freeze
    TWINS = [%w[brgen_old_light brgen_old_dark], %w[light social]].freeze

    # One dialect's two modes, each a block of colours and the prefix its keys carry.
    Mode = Data.define(:block, :prefix) do
      def ratios = NAMES.to_h { |role| [role, ratio(role)] }

      def ratio(role)
        ground = DialectContrast.rgb(block["#{prefix}bg"]) or return
        ink = ROLES.fetch(role).filter_map { |name| DialectContrast.rgb(block["#{prefix}#{name}"]) }.first or return
        Deploy::RenderedDesign.contrast(ink, ground)
      end
    end

    module_function

    def rgb(hex) = hex.to_s[/\A#(\h{6})\z/, 1]&.then { |digits| digits.scan(/../).map(&:hex) + [1] }

    def both_modes?(block) = block.is_a?(Hash) && block.key?("light_bg") && block.key?("dark_bg")

    # [name, light ratios, dark ratios] for every dialect that has both modes.
    def pairs(tokens)
      inline = tokens.select { |_name, block| both_modes?(block) }.map do |name, block|
        [name, Mode.new(block, "light_").ratios, Mode.new(block, "dark_").ratios]
      end
      inline + twins(tokens)
    end

    def twins(tokens)
      TWINS.filter_map do |light, dark|
        next unless tokens[light].is_a?(Hash) && tokens[dark].is_a?(Hash)

        ["#{light}/#{dark}", Mode.new(tokens[light], "").ratios, Mode.new(tokens[dark], "").ratios]
      end
    end

    def floors(name, modes)
      FLOOR.flat_map do |role, floor|
        modes.filter_map do |mode, ratios|
          value = ratios[role]
          "#{name} #{mode} #{role} is #{value}:1, under #{floor}:1" if value && value < floor
        end
      end
    end

    def drifts(name, modes)
      DRIFT.filter_map do |role|
        light, dark = modes.values.map { |ratios| ratios[role] }
        apart = light && dark && (light - dark).abs > [light, dark].max * 0.35
        "#{name} #{role} is #{light}:1 light and #{dark}:1 dark, more than 35% apart" if apart
      end
    end

    def findings(src)
      tokens = YAML.safe_load(src, aliases: true)&.fetch("tokens", nil)
      return [] unless tokens.is_a?(Hash)

      pairs(tokens).flat_map do |name, light, dark|
        modes = { "light" => light, "dark" => dark }
        (floors(name, modes) + drifts(name, modes)).map { |message| [name.split("/").first, message] }
      end
    rescue Psych::Exception # scan: intentional - a tokens file that does not parse is YAML_SYNTAX's finding
      []
    end

    def fixture(border)
      { "tokens" => { "luxury" => { "light_bg" => "#efefef", "light_text" => "#333333", "light_muted" => "#4d4d4d",
                                    "light_border" => "#888888", "dark_bg" => "#000000", "dark_text" => "#efefef",
                                    "dark_muted" => "#999999", "dark_border" => border } } }.to_yaml
    end
  end

  Law.define(:DIALECT_CONTRAST_PARITY) do
    source "Albers, Interaction of Color (1963); WCAG 1.4.3; operator 2026-11-06: 4.5:1 minimum, 7:1 for body text"
    tags %i[DESIGN ACCESSIBILITY]
    path %r{MASTER/data/tokens\.yml\z}
    example_path "/repo/MASTER/data/tokens.yml"
    fix "Bring the drifting role into the band in both modes: muted >= 4.5:1, text >= 7:1, borders within 35%."
    bad DialectContrast.fixture("#222222")
    good DialectContrast.fixture("#666666")
    check do |src, _path|
      DialectContrast.findings(src).map do |block, message|
        finding(line: (src.lines.index { |line| line.match?(/\A  #{Regexp.escape(block)}:/) } || 0) + 1, message:)
      end
    end
  end
end
