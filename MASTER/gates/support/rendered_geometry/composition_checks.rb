# frozen_string_literal: true

module Deploy
  class RenderedGeometryGate
    # The first screen as a composition rather than as boxes: how many type
    # sizes it shows, whether the h1 stands clear of the body text, and whether
    # long text is centred, on the first screen and in any block that centres
    # more than a few lines. They read the probe's "visual" block and each
    # element's unrounded rect, and design_rules' typography.hierarchy and
    # layout_rules.alignment.
    #
    # A module included back into the gate, like PlacementChecks beside it, so
    # it keeps @rules and @result.
    module CompositionChecks
      private

      # layout_rules.alignment.center_text_max_lines. Centred text gives the eye no
      # fixed left edge to return to, so every line after the third costs the
      # reader a hunt for where it starts. Only measurable once rendered, because
      # the line count depends on the box the text landed in.
      def check_centered_prose(surface, elements)
        max_lines = @rules.dig("layout_rules", "alignment", "center_text_max_lines").to_i
        return if max_lines <= 0

        offenders = elements.filter_map do |el|
          next unless el["visible"] && el["onscreen"]
          next unless el["text_align"].to_s == "center"
          # Own text only. Dividing a *container's* height by its line-height
          # counts its icon, heading, button and padding as prose: the shared
          # empty state reported 12 lines where the sentence is two. A block that
          # holds no text of its own is a layout box, and centring it is not the
          # thing this rule is about.
          next if el["text"].to_s.strip.empty?

          lh = el["line_height"].to_f
          next if lh <= 0

          lines = (el["frect"]&.dig("h").to_f / lh).round
          next if lines <= max_lines

          "#{el["key"]} (#{lines} lines)"
        end
        return if offenders.empty?

        @result.fail(
          "geometry centered_prose: #{surface.id} centres #{offenders.size} block(s) past " \
          "#{max_lines} lines — #{offenders.first(3).join('; ')} (principle=alignment)", severity: :soft
        )
      end

      def check_visual_composition(surface, data)
        visual = data["visual"] || {}
        first = visual["first_screen"] || {}
        typography = visual["typography"] || {}
        sizes = Array(typography["distinct_font_sizes"]).map(&:to_f).select(&:positive?)
        max_sizes = @rules.dig("typography", "hierarchy", "max_font_sizes").to_i
        if max_sizes.positive? && sizes.size > max_sizes
          @result.fail(
            "geometry composition: #{surface.id} first screen renders #{sizes.size} type sizes > " \
            "#{max_sizes} allowed — reduce the visual vocabulary (principle=typography)",
            severity: :soft
          )
        end

        heading = Array(typography["heading_sizes"]).find { |row| row["tag"] == "h1" }&.fetch("px", nil)
        body = typography["body_median_px"].to_f
        if heading.to_f.positive? && body.positive? && heading < body * 1.4
          @result.fail(
            "geometry composition: #{surface.id} h1 is #{heading}px vs median body #{body.round(1)}px — " \
            "hierarchy is visually weak (principle=hierarchy)",
            severity: :soft
          )
        end

        long_centered = first["centered_long_text"].to_i
        return if long_centered.zero?

        @result.fail(
          "geometry composition: #{surface.id} has #{long_centered} long centered text block(s) " \
          "in the first screen — prefer a readable measure and directional alignment (principle=alignment)",
          severity: :soft
        )
      end
    end
  end
end
