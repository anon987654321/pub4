# frozen_string_literal: true

module Deploy
  module DesignMetrics
    # WCAG and APCA colour maths, split out of design_metrics.rb when that file
    # crossed the 300-line limit with no ceiling recorded — the case
    # file_length_ratchet_test exists to catch, and the only one of its twelve
    # entries that was a genuinely new long file rather than an existing one
    # growing by a few lines.
    #
    # Plain instance methods rather than module_function, because DesignMetrics
    # `extend`s this: that turns them into public singleton methods there, so
    # every existing caller — DesignMetrics.contrast_ratio, .apca_lc,
    # .parse_hex, all 24 of them across five files — keeps working unchanged.
    # Contrast.contrast_ratio also resolves, for a caller that wants to name
    # which half it is reaching for.
    module Contrast
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

      # APCA (Accessible Perceptual Contrast Algorithm), W3C draft constants
      # 0.1.9. Reported alongside the WCAG 2.x ratio above, never instead of it:
      # WCAG 2.x is what style.yml declares and what an auditor will measure.
      #
      # It is worth measuring both because the two disagree in a way that matters
      # here. WCAG 2.x is a ratio of two luminances and is symmetric — it gives
      # the same answer whether the text is dark on light or light on dark — while
      # perceived contrast is not symmetric at all. Light text on a dark ground
      # spreads into its background (halation) and reads thinner than the ratio
      # predicts; mid-greys on light grounds read better than it predicts. A
      # graphite/indigo dark UI is exactly where that error lives, so a secondary
      # tier "failing" AAA by 0.2 may be perceptually fine, and something WCAG
      # passes may not be.
      #
      # APCA returns a signed lightness contrast Lc, roughly -108..106. The sign
      # carries polarity; readability thresholds use its absolute value.
      APCA = {
        trc: 2.4, r: 0.2126729, g: 0.7151522, b: 0.0721750,
        norm_bg: 0.56, norm_txt: 0.57, rev_txt: 0.62, rev_bg: 0.65,
        blk_thrs: 0.022, blk_clmp: 1.414, scale: 1.14,
        lo_offset: 0.027, delta_y_min: 0.0005, lo_clip: 0.1
      }.freeze

      def apca_screen_luminance(rgb)
        k = APCA
        y = k[:r] * ((rgb[0] / 255.0)**k[:trc]) +
            k[:g] * ((rgb[1] / 255.0)**k[:trc]) +
            k[:b] * ((rgb[2] / 255.0)**k[:trc])
        # Soft clamp near black: below this the display's own flare dominates.
        y < k[:blk_thrs] ? y + ((k[:blk_thrs] - y)**k[:blk_clmp]) : y
      end

      # Lc for text `hex_txt` on background `hex_bg`. Order matters — unlike the
      # WCAG ratio, swapping the arguments changes the answer.
      def apca_lc(hex_txt, hex_bg)
        txt = parse_hex(hex_txt)
        bg = parse_hex(hex_bg)
        return nil unless txt && bg

        k = APCA
        y_txt = apca_screen_luminance(txt)
        y_bg = apca_screen_luminance(bg)
        return 0.0 if (y_bg - y_txt).abs < k[:delta_y_min]

        if y_bg > y_txt # dark text on a light ground
          s = ((y_bg**k[:norm_bg]) - (y_txt**k[:norm_txt])) * k[:scale]
          c = s < k[:lo_clip] ? 0.0 : s - k[:lo_offset]
        else # light text on a dark ground
          s = ((y_bg**k[:rev_bg]) - (y_txt**k[:rev_txt])) * k[:scale]
          c = s > -k[:lo_clip] ? 0.0 : s + k[:lo_offset]
        end
        (c * 100).round(1)
      end

      # APCA's readability thresholds are a lookup over size and weight, not one
      # number. This is the conservative reading of the bronze-level table: body
      # copy wants Lc 75, larger or bolder text 60, and anything at 45 is a
      # headline floor rather than a reading target.
      def apca_threshold(size_px, bold: false)
        size = size_px.to_f
        return 45.0 if size >= 36 || (size >= 24 && bold)
        return 60.0 if size >= 24 || (size >= 18.66 && bold)

        75.0
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
    end
  end
end
