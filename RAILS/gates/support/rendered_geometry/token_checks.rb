# frozen_string_literal: true

module Deploy
  class RenderedGeometryGate
    # The palette half of the gate: which text colours the browser actually
    # painted, against the colours design_tokens.yml sanctions.
    #
    # A module included back into the gate, so it keeps @result, @tokens and the
    # finding helpers it shares with the other checks. Nothing in here builds a
    # path from __dir__ — the design_metrics split moved a css_budget.yml path
    # one directory deeper and silently ran that gate unbudgeted.
    module TokenChecks
      def check_token_conformance(surface, data)
        colors = data["colors"] || {}
        rogue = colors.reject { |hex, _| @palette.include?(hex.to_s.downcase) }
        return if rogue.empty?

        top = rogue.sort_by { |_, count| -count }.first(4)
        @result.fail(
          "geometry tokens: #{surface.id} renders #{rogue.size} text colour(s) outside design_tokens.yml — " \
          "#{top.map { |hex, count| "#{hex}×#{count}" }.join(', ')} principle=exact_token_use",
          severity: :soft
        )
      end

      # Every colour the design system actually sanctions, plus the achromatic
      # extremes every UI legitimately renders.
      # Walk the whole tree, not just one level. design_tokens.yml nests
      # vertical_accents as `messenger: { accent: "#6b7fd7", hover: "#5566c4" }`,
      # so a one-level each_value saw a Hash where it expected a hex and skipped
      # every vertical accent in the file. The channel pages were then reported as
      # painting #6b7fd7 "outside design_tokens.yml" — a colour that is declared
      # in design_tokens.yml, on the line above its own contrast measurement.
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
