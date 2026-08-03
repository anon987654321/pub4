# frozen_string_literal: true

module Deploy
  # Pure-Ruby design measurements against MASTER/data/design_rules.yml.
  # No browser required. Used by DesignMetricsGate + unit tests.
  module DesignMetrics
    module_function

    # WCAG relative luminance for sRGB hex (#rgb / #rrggbb).
    def parse_hex(color)
      s = color.to_s.strip
      return nil if s.empty? || s.start_with?("var(", "oklch", "color-mix", "rgb")

      s = s.delete_prefix("#")
      case s.length
      when 3 then s = s.chars.map { |c| c * 2 }.join
      when 6 then # ok
      else return nil
      end
      return nil unless s.match?(/\A[0-9a-fA-F]{6}\z/)

      s.scan(/../).map { |h| h.to_i(16) }
    end

    def relative_luminance(rgb)
      r, g, b = rgb.map do |c|
        v = c / 255.0
        v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055)**2.4
      end
      0.2126 * r + 0.7152 * g + 0.0722 * b
    end

    def contrast_ratio(hex_a, hex_b)
      a = parse_hex(hex_a)
      b = parse_hex(hex_b)
      return nil unless a && b

      l1 = relative_luminance(a)
      l2 = relative_luminance(b)
      lighter, darker = [l1, l2].sort.reverse
      ((lighter + 0.05) / (darker + 0.05)).round(2)
    end

    # Nudge a foreground hex along the luminance axis until it clears `target`
    # against `bg`, preserving hue and saturation. Returns nil when even pure
    # black or white cannot reach the target (a background that light or dark
    # needs a different background, not a different text colour).
    #
    # Used to *suggest* a value in gate output. Token colours are brand
    # decisions and are deliberately never rewritten automatically.
    def suggest_contrast_fix(fg_hex, bg_hex, target)
      fg = parse_hex(fg_hex)
      bg = parse_hex(bg_hex)
      return nil unless fg && bg

      toward = relative_luminance(bg) > 0.5 ? [0, 0, 0] : [255, 255, 255]
      best = nil
      # 40 steps at 2.5% each covers the full range with sub-perceptual jumps.
      (1..40).each do |step|
        t = step / 40.0
        candidate = fg.each_with_index.map { |c, i| (c + (toward[i] - c) * t).round }
        hex = "#" + candidate.map { |c| c.to_s(16).rjust(2, "0") }.join
        ratio = contrast_ratio(hex, bg_hex)
        next unless ratio && ratio >= target

        best = { hex: hex, ratio: ratio }
        break
      end
      best
    end

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

    def vertical_accent_pairs(tokens)
      verticals = tokens["vertical_accents"]
      social = tokens["social"]
      return [] unless verticals.is_a?(Hash) && social.is_a?(Hash)

      verticals.flat_map do |vertical, row|
        next [] unless row.is_a?(Hash)

        row.slice("accent", "hover").flat_map do |key, fg|
          VERTICAL_BACKGROUNDS.filter_map do |bg_key|
            bg = social[bg_key]
            ratio = bg && contrast_ratio(fg, bg)
            next unless ratio

            { label: "vertical_accents.#{vertical}_#{key}/social.#{bg_key}", fg: fg, bg: bg,
              fg_key: "#{vertical}_#{key}", bg_key: bg_key, ratio: ratio }
          end
        end
      end
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
