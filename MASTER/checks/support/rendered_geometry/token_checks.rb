# frozen_string_literal: true

module Deploy
  class RenderedGeometryCheck
    # The palette half of the check: which text colours the browser actually
    # painted, against the colours sanctioned by MASTER/data/tokens.yml.
    #
    # A module included back into the check, so it keeps @result, @tokens and the
    # finding helpers it shares with the other checks. Nothing in here builds a
    # path from __dir__ — the design_metrics split moved a css_budget.yml path
    # one directory deeper and silently ran that check unbudgeted.
    module TokenChecks
      def check_token_conformance(surface, data)
        check_computed_values(surface, data["elements"])
        colors = data["colors"] || {}

        rogue = colors.reject { |hex, _| @palette.include?(hex.to_s.downcase) }
        return if rogue.empty?

        top = rogue.sort_by { |_, count| -count }.first(4)
        @result.fail(
          "geometry tokens: #{surface.id} renders #{rogue.size} text colour(s) outside MASTER/data/tokens.yml - " \
          "#{top.map { |hex, count| "#{hex}x#{count}" }.join(', ')} principle=exact_token_use",
          severity: :soft,
        )
      end

      # The values the browser computed, against tokens.yml, one finding per Law. Source lints
      # read what was written; this reads what reached the element after rem, inheritance and
      # the cascade, so 0.75rem under brgen's 18px root is the 13.5px it renders as.
      COMPUTED_LAWS = {
        spacing: "EIGHT_PX_RHYTHM", leading: "LINE_HEIGHT_ON_SCALE", radius: "RENDERED_VALUES",
        palette: "MAGIC_COLOR", type_pixel: "PIXEL_EXACT", type_scale: "TYPE_HIERARCHY"
      }.freeze

      def check_computed_values(surface, elements)
        check_space(surface, elements)
        shown = Array(elements).select { |el| el["visible"] }
        computed_offenders(shown).each do |kind, rows|
          next if rows.empty?

          sample = rows.uniq.first(4).join("; ")
          @result.fail("geometry #{kind}: #{surface.id} #{rows.size} computed value(s) off MASTER/data/tokens.yml - " \
                       "#{sample} law=#{COMPUTED_LAWS.fetch(kind)}", severity: :soft)
        end
      end

      def computed_offenders(elements)
        {
          spacing: elements.flat_map { |el| off_spacing(el) },
          leading: elements.filter_map { |el| off_leading(el) },
          radius: elements.filter_map { |el| off_radius(el) },
          palette: elements.flat_map { |el| off_palette(el) },
          type_pixel: elements.filter_map { |el| fractional_size(el) },
          type_scale: type_scale_excess(elements),
        }
      end

      SPACING_SIDES = %w[padding-top padding-right padding-bottom padding-left margin-top margin-bottom row-gap
                         column-gap].freeze

      # On the 8px rhythm with its 4px fine step, or a step tokens.yml declares (the 1-3px hairlines).
      def on_spacing_scale?(length)
        magnitude = length.abs
        (magnitude % 4).abs < 0.05 || @allowed_spacing.any? { |step| (step - magnitude).abs < 0.05 }
      end

      def off_spacing(element)
        Array(element["spacing"]).zip(SPACING_SIDES).filter_map do |px, side|
          "#{element["key"]} #{side} #{px}px" if px && !on_spacing_scale?(px)
        end
      end

      def off_leading(element)
        size = element["font_size"].to_f
        leading = element["line_height"].to_f
        return if size <= 0 || leading <= 0 || element["text"].to_s.strip.empty?

        ratio = leading / size
        return if scale_steps("line_height").any? { |step| (step - ratio).abs < 0.02 }

        "#{element["key"]} line-height #{leading}px on #{size}px (#{ratio.round(2)})"
      end

      # A radius of half the box or more is a circle or a pill, a shape rather than a step.
      def off_radius(element)
        half = element.fetch("rect", {}).values_at("w", "h").map(&:to_f).min.to_f / 2
        corners = element["border_radius"].to_s.scan(/(-?[\d.]+)px/).flatten.map(&:to_f)
        odd = corners.reject { |px| px >= half - 0.5 || scale_steps("radius_px").include?(px) }
        "#{element["key"]} border-radius #{odd.first}px" if odd.any?
      end

      def off_palette(element)
        # Text colour is check_token_conformance's; this adds the ground it is painted on.
        %w[bg].filter_map do |field|
          hex = element[field].to_s.downcase
          "#{element["key"]} #{field} #{hex}" if hex.start_with?("#") && !@palette.include?(hex)
        end
      end

      def fractional_size(element)
        size = element["font_size"].to_f
        return unless size.positive? && (size % 1).abs > 0.05 && !element["text"].to_s.strip.empty?

        "#{element["key"]} font-size #{size}px"
      end

      def type_scale_excess(elements)
        limit = (@rules.dig("typography", "hierarchy", "max_font_sizes") || 8).to_i
        sizes = elements.filter_map { |el| el["font_size"].to_f if !el["text"].to_s.strip.empty? }.uniq.sort
        sizes.size > limit ? ["#{sizes.size} distinct font sizes over #{limit} (#{sizes.join(", ")}px)"] : []
      end

      def scale_steps(name) = Array(@tokens.dig("scale", name)).map(&:to_f)

      # Every colour the design system actually sanctions, plus the achromatic
      # extremes every UI legitimately renders.
      # Walk the whole tree, not just one level. MASTER/data/tokens.yml nests
      # vertical_accents as `messenger: { accent: "#6b7fd7", hover: "#5566c4" }`,
      # so a one-level each_value saw a Hash where it expected a hex and skipped
      # every vertical accent in the file. The channel pages were then reported as
      # painting #6b7fd7 "outside MASTER/data/tokens.yml" — a colour that is declared
      # in MASTER/data/tokens.yml, on the line above its own contrast measurement.
      def token_palette
        set = %w[#000000 #ffffff]

        collect_hexes(@tokens, set)
        set.compact.uniq
      end

      def collect_hexes(node, set)
        case node
        when Hash then node.each_value { |v| collect_hexes(v, set) }
        when Array then node.each { |v| collect_hexes(v, set) }
        else
          v = node.to_s.strip.downcase
          set << expand_hex(v) if v.match?(/\A#[0-9a-f]{3}([0-9a-f]{3})?\z/)
        end
      end

      def expand_hex(value)
        s = value.delete_prefix("#")
        s = s.chars.map { |c| c * 2 }.join if s.length == 3
        "##{s}"
      end
    end
  end
end
