# frozen_string_literal: true

require "set"
require_relative "design_metrics/contrast"

module Deploy
  # Pure-Ruby design measurements against MASTER/data/rules.yml design_rules.
  # No browser required. Used by DesignMetricsGate + unit tests.
  module DesignMetrics
    extend Contrast

    module_function

    # Which token keys read as foreground vs background, and which light/dark
    # mode they belong to. Pairing a light-mode text colour against a dark-mode
    # surface would invent a combination the UI never renders.
    MODE_PREFIX = /\A(light|dark)_/
    FOREGROUND_KEY = /\A(?:light_|dark_)?(text|text_secondary|muted|accent|accent_hover|link|danger)\z/
    BACKGROUND_KEY = /\A(?:light_|dark_)?(bg|surface|surface_elevated|search_bg|chrome_bg)\z/

    # brgen's vertical accents sit in their own top-level map with no background
    # of their own, so token_pairs -- which only pairs inside one dialect -- never
    # saw them. They render on the social chrome. Paired against it, marketplace
    # (#8c7a5e, 4.33:1) and tv (#d6473f, 4.14:1) are both under WCAG AA, and
    # nothing had reported either.
    VERTICAL_BACKGROUNDS = %w[bg surface_elevated].freeze

    # Against the surfaces brgen actually paints, which are not social's.
    #
    # This paired every vertical accent with social.bg (#17161c) and
    # social.surface_elevated (#211f28). brgen's dark theme is brgen_old_dark —
    # _root.scss includes brgen-old-dark-tokens, whose later :root wins — so the
    # real surfaces are #000000 and #1a1a1a. Every vertical finding was measured
    # against a background the app never renders.
    #
    # It mattered in both directions. marketplace #8c7a5e reads 3.92:1 on
    # social.surface_elevated and 4.19 on the real one — still failing, so the
    # lift was right for the wrong reason. messenger #6b7fd7 reads 4.37 on
    # social's and 4.68 on the real one — it already passed, and was "corrected"
    # for nothing.
    VERTICAL_SURFACE_DIALECT = "brgen_old_dark"

    # Vertical accents used only inside a light-theme block.
    #
    # The comment on MODE_PREFIX above states the rule this enforces — pairing a
    # light-mode foreground against a dark-mode surface invents a combination
    # the UI never renders — and MODE_PREFIX cannot reach these, because
    # vertical_accents carry no light_/dark_ prefix. So the mode is read from
    # the stylesheets instead of from the key.
    #
    # marketplace is the case. --vertical-marketplace-accent-hover has exactly
    # one use in the whole tree, at _vertical_marketplace.scss:73, under
    # `:root[data-theme="light"]` — and design_tokens.yml says why in the note
    # above the token: the accent is a background carrying dark ink, so small
    # text in this vertical wears `hover`, and only the light theme swaps to it.
    # On its actual ground it measures 6.03:1. Paired against brgen_old_dark's
    # #000000 and #1a1a1a it reads 3.48 and 2.89, and reported two AA failures
    # for a combination that cannot be rendered.
    #
    # Raising the ceiling to absorb those would have been worse than the finding:
    # contrast_below_aa is 0 precisely so a real one is visible the day it lands.
    def light_only_vertical_keys(rails_root)
      globs = %w[
        {shared,brgen,amber,bsdports}/app/assets/stylesheets/**/*.scss
        brgen/engines/*/app/assets/stylesheets/*.scss
      ]
      light_only = {}
      globs.each do |pattern|
        Dir.glob(File.join(rails_root, pattern)).each do |path|
          next if path.include?("/builds/") || path.include?("/public/assets/") ||
                  path.include?("/vendor/") || path.include?("/node_modules/")

          theme = nil
          File.readlines(path).each do |line|
            theme = "light" if line.include?('data-theme="light"')
            theme = "dark" if line.include?('data-theme="dark"')
            theme = nil if line.strip == "}"
            line.scan(/--vertical-(\w+)-accent-(\w+)/) do |vertical, key|
              token = "#{vertical}_#{key}"
              # Any use outside a light block disqualifies it for good.
              light_only[token] = false unless theme == "light"
              light_only[token] = true unless light_only.key?(token)
            end
          end
        rescue StandardError
          next
        end
      end
      light_only.select { |_, only| only }.keys
    end

    def vertical_accent_pairs(tokens, rails_root = nil)
      verticals = tokens["vertical_accents"]
      social = tokens[VERTICAL_SURFACE_DIALECT] || tokens["social"]
      return [] unless verticals.is_a?(Hash) && social.is_a?(Hash)

      # Computed once, not per vertical.
      light_only = rails_root ? light_only_vertical_keys(rails_root) : []

      verticals.flat_map do |vertical, row|
        next [] unless row.is_a?(Hash)

        row.slice("accent", "hover").reject { |key, _| light_only.include?("#{vertical}_#{key}") }
           .flat_map do |key, fg|
          VERTICAL_BACKGROUNDS.filter_map do |bg_key|
            bg = social[bg_key]
            ratio = bg && contrast_ratio(fg, bg)
            next unless ratio

            { label: "vertical_accents.#{vertical}_#{key}/#{VERTICAL_SURFACE_DIALECT}.#{bg_key}", fg: fg, bg: bg,
              fg_key: "#{vertical}_#{key}", bg_key: bg_key, ratio: ratio }
          end
        end
      end
    end

    # Values of a custom property that survive the cascade.
    #
    # read_custom_properties below answers "is this property read anywhere",
    # which is necessary and not sufficient. A dialect can declare a value, the
    # property can be read all over the tree, and the value still never reach a
    # pixel because a later rule at the same specificity overwrites it.
    #
    # That is what social.accent does. Every app emits `:root { --accent:
    # #897dda }` from the shared baseline and then a second `:root` further down
    # with its own dialect — #f2f2f2 for brgen's BRGEN_OLD grayscale, #7e6e55 for
    # amber's luxury, #63c363 for bsdports' wscons. Same specificity, later wins,
    # so the social value is shadowed in all three. Measured: with the accent
    # "corrected" locally and production still on the old value, both computed
    # --accent as #f2f2f2. Identical. The contrast finding that prompted the
    # change was about a colour nothing paints.
    #
    # Deliberately reads the built CSS, unlike read_custom_properties, which
    # excludes builds/ so a stale artifact cannot vote. Cascade order only exists
    # after compilation — the SCSS says which mixins exist, not which one lands
    # last in a given app. The freshness risk is real and is covered by
    # `build_all_css.rb --check` and the generated_asset gate; if those are
    # skipped this reads yesterday's answer.
    #
    # Scope: plain `:root` shadowing, which is the demonstrated defect. It does
    # not resolve @media, [data-theme], or body-class scopes — a value at a more
    # specific selector (body.vertical-marketplace) is treated as painting,
    # which is correct for those and conservative elsewhere.
    def winning_property_values(rails_root, prop)
      @winning_property_values ||= {}
      @winning_property_values[[rails_root, prop]] ||= begin
        values = Set.new
        Dir.glob(File.join(rails_root, "*/app/assets/builds/application.css")).each do |path|
          css = File.read(path) rescue next
          decls = []
          css.scan(/([^{}]+)\{([^{}]*)\}/) do
            selector = Regexp.last_match(1)
            body = Regexp.last_match(2)
            body.scan(/(?:\A|;)\s*#{Regexp.escape(prop)}\s*:\s*([^;]+)/) do
              decls << [selector.strip.split(",").map(&:strip), Regexp.last_match(1).strip.downcase]
            end
          end
          # Among bare `:root` rules only the last one is the default winner.
          bare = decls.each_index.select { |i| decls[i][0] == [":root"] }
          bare[0..-2].to_a.each { |i| decls[i] = nil }
          decls.compact.each { |_, v| values << v }
        end
        values
      end
    end

    # Does this dialect's declared value survive the cascade under any of the
    # CSS names the token can take?
    def token_value_wins?(rails_root, fg_key, value)
      custom_property_candidates(fg_key).any? { |prop| token_value_paints?(rails_root, prop, value) }
    end

    def token_value_paints?(rails_root, prop, value)
      return true if value.nil? || value.to_s.strip.empty?

      winning = winning_property_values(rails_root, prop)
      # No declarations found at all (property lives outside the built sheets) —
      # do not silence a finding on the strength of a failed lookup.
      return true if winning.empty?

      winning.include?(value.to_s.strip.downcase)
    end

    # Custom properties actually read by something, as `var(--name`.
    #
    # A contrast finding is only worth a reader's attention if the colour it
    # measures reaches a pixel. design_tokens.yml declares several that no longer
    # do -- every *_hover value among them, since --accent-hover and
    # --vertical-<v>-accent-hover have no var() consumer anywhere in the tree --
    # so a third of the contrast list was about colours nothing paints, and the
    # count could never reach zero by fixing CSS.
    #
    # Same rule the rest of this repo applies to declarations: find the reader
    # before trusting one.
    def read_custom_properties(rails_root)
      @read_custom_properties ||= {}
      @read_custom_properties[rails_root] ||= begin
        globs = %w[
          {shared,brgen,amber,bsdports}/app/assets/stylesheets/**/*.scss
          brgen/engines/*/app/assets/stylesheets/*.scss
          {shared,brgen,amber,bsdports}/app/**/*.erb
          brgen/engines/*/app/**/*.erb
          shared/frontend/**/*.js
          {shared,brgen,amber,bsdports}/app/javascript/**/*.js
        ]
        names = Set.new
        globs.each do |pattern|
          Dir.glob(File.join(rails_root, pattern)).each do |path|
            next if path.include?("/builds/") || path.include?("/public/assets/") ||
                    path.include?("/vendor/") || path.include?("/node_modules/")

            File.read(path).scan(/var\(\s*(--[\w-]+)/) { |m| names << m.first }
          rescue StandardError
            next
          end
        end
        names
      end
    end

    # Candidate CSS names for a token key, since design_tokens.yml and the
    # stylesheets spell the same colour differently: `light_accent` is --accent
    # inside a light block, and `marketplace_hover` is
    # --vertical-marketplace-accent-hover.
    def custom_property_candidates(fg_key)
      key = fg_key.to_s
      base = key.sub(MODE_PREFIX, "")
      cands = ["--#{base.tr('_', '-')}", "--#{key.tr('_', '-')}"]
      if (m = base.match(/\A(?<vertical>[a-z]+)_(?<kind>accent|hover)\z/))
        if m[:kind] == "accent"
          # _vertical_shell.scss:27 assigns each vertical's accent straight to
          # --accent under body.vertical-<v>, so these paint through the token
          # every surface already reads. The --vertical-<v>-accent alias beside
          # it has no consumer, and checking only that name skipped the very
          # findings vertical_accent_pairs was written to surface (see its
          # header: marketplace 4.33:1 and tv 4.14:1 on social chrome, "and
          # nothing had reported either").
          cands << "--accent"
          cands << "--vertical-#{m[:vertical]}-accent"
        else
          cands << "--vertical-#{m[:vertical]}-accent-hover"
        end
      end
      cands.uniq
    end

    def token_painted?(rails_root, fg_key)
      read = read_custom_properties(rails_root)
      custom_property_candidates(fg_key).any? { |c| read.include?(c) }
    end

    # All plausible fg/bg pairings within a dialect, mode-matched.
    def token_pairs(dialect_name, dialect)
      return [] unless dialect.is_a?(Hash)

      mode = ->(key) { key.to_s[MODE_PREFIX, 1] }
      fgs = dialect.keys.select { |k| k.to_s.match?(FOREGROUND_KEY) }
      bgs = dialect.keys.select { |k| k.to_s.match?(BACKGROUND_KEY) }
      pairs = []
      fgs.each do |fg|
        bgs.each do |bg|
          next unless mode.call(fg) == mode.call(bg)

          fg_value = dialect[fg]
          bg_value = dialect[bg]
          next unless fg_value && bg_value

          ratio = contrast_ratio(fg_value, bg_value)
          next unless ratio

          pairs << { label: "#{dialect_name}.#{fg}/#{bg}", fg: fg_value, bg: bg_value,
                     fg_key: fg, bg_key: bg, ratio: ratio }
        end
      end
      pairs
    end

    # rem/em/px → px assuming 16px root
    def to_px(value, root_px: 16.0)
      s = value.to_s.strip
      case s
      when /\A(-?[\d.]+)px\z/i then Regexp.last_match(1).to_f
      when /\A(-?[\d.]+)rem\z/i then Regexp.last_match(1).to_f * root_px
      when /\A(-?[\d.]+)em\z/i then Regexp.last_match(1).to_f * root_px
      when /\A(-?[\d.]+)\z/ then Regexp.last_match(1).to_f
      else nil
      end
    end

    def extract_declarations(css, property)
      prop = Regexp.escape(property)
      css.to_s.scan(/#{prop}\s*:\s*([^;}+{]+)/i).flatten.map(&:strip)
    end

    def extract_min_heights(css)
      extract_declarations(css, "min-height").filter_map { |v| to_px(v) }
    end

    def extract_line_heights(css)
      extract_declarations(css, "line-height").filter_map do |v|
        next v.to_f if v.match?(/\A[\d.]+\z/)

        # unitless preferred; skip multi-value / normal
        nil
      end
    end

    def extract_font_sizes_px(css, root_px: 16.0)
      extract_declarations(css, "font-size").filter_map { |v| to_px(v, root_px: root_px) }
    end

    def extract_ch_measures(css)
      css.to_s.scan(/max-width\s*:\s*([\d.]+)\s*ch/i).flatten.map(&:to_f)
    end

    def extract_spacing_px(css, root_px: 16.0)
      props = %w[margin padding gap row-gap column-gap margin-block margin-inline padding-block padding-inline]
      values = []
      props.each do |prop|
        extract_declarations(css, prop).each do |raw|
          raw.split(/\s+/).each do |token|
            px = to_px(token, root_px: root_px)
            values << px if px && px.positive?
          end
        end
      end
      values
    end

    # 8px rhythm: allow exact allowed list or multiples of base with hairline 4.
    def off_rhythm?(px, allowed:, base: 8)
      return false if allowed.include?(px.to_i)
      return false if (px % base).zero?
      return false if px == 4 || (px % 4).zero? && px < base # hairline

      true
    end

    def type_scale_ratio(sizes_px)
      uniq = sizes_px.map { |s| s.round(2) }.uniq.sort
      return nil if uniq.size < 2

      ratios = uniq.each_cons(2).map { |a, b| (b / a).round(3) }
      ratios
    end

    # Interactive selector clusters that must declare Fitts-safe min-height somewhere nearby.
    INTERACTIVE_NEEDLES = [
      [/\.btn\b/, "button .btn"],
      [/\.tab-item\b|\.tab-bar\b/, "mobile tab bar"],
      [/\.swipe-action\b/, "dating swipe"],
      [/\.feed-action\b/, "feed action"],
      [/listing-buy-bar|\.deal-fav\b/, "marketplace buy/fav"],
      [/\.compose-submit\b|\.compose-box\b/, "compose"],
      [/\.channel-composer\b/, "channel composer"],
    ].freeze

    def extract_box_mins(css)
      %w[min-height min-width height width].flat_map do |prop|
        extract_declarations(css, prop).filter_map { |v| to_px(v) }
      end
    end

    def interactive_touch_coverage(css_by_path, min_px:)
      findings = []
      INTERACTIVE_NEEDLES.each do |needle, label|
        paths = css_by_path.select { |_p, body| body.match?(needle) }.keys
        next if paths.empty?

        covered = paths.any? do |p|
          body = css_by_path[p]
          # Accept min-height/width or explicit height/width ≥ Fitts floor.
          # Also treat CSS vars named --space-12+ / --touch as covered (tokenized Fitts).
          extract_box_mins(body).any? { |h| h + 0.01 >= min_px } ||
            body.match?(/--space-(1[2-9]|[2-9]\d)|--touch|min-height:\s*44px|height:\s*44px|width:\s*var\(--space-1[2-9]/i)
        end
        findings << { label: label, paths: paths, covered: covered }
      end
      findings
    end
  end
end
