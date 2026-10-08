# frozen_string_literal: true

module Deploy
  # gap_over_margin and card_padding_px were read as config keys and never
  # applied to a stylesheet. These two tallies are that application.
  module CssSpacingScans
    CARD_CLASS = /(?:^|[\s,>+~])\.card(?=$|[\s,{:#\[.>+~])/
    MARGIN_PROP = /\A\s*margin(?:-(?:top|right|bottom|left|block|inline)(?:-(?:start|end))?)?\s*:\s*([^;}]+)/
    PADDING_PROP = /\A\s*padding(?:-(?:top|right|bottom|left|block|inline)(?:-(?:start|end))?)?\s*:\s*([^;}]+)/
    ZERO = /\A(?:0(?:px|em|rem|%)?|0(?:\s+0(?:px|em|rem|%)?){1,3})\z/

    def scan_spacing(rel, body)
      selector = +""
      pending = +""
      strip_comments(body).each_line.with_index do |line, index|
        stripped = line.strip
        next if stripped.empty? || stripped.start_with?("*", "//")

        if stripped.include?("{")
          head, rest = stripped.split("{", 2)
          selector = "#{pending} #{head}".strip
          pending = +""
          inspect_props(rel, index + 1, selector, rest.to_s)
        elsif stripped.include?(":")
          inspect_props(rel, index + 1, selector, stripped)
        else
          pending = "#{pending} #{stripped}".strip
        end
        selector = +"" if stripped.include?("}")
      end
    end

    def inspect_props(rel, line_no, selector, fragment)
      fragment.split(";").each do |decl|
        if selector.include?(">") && (m = decl.match(MARGIN_PROP))
          value = m[1].strip
          next if value.match?(ZERO) || value.start_with?("var(", "auto")

          @tally["child_margin"] << "#{rel}:#{line_no}"
        end
        next unless selector.match?(CARD_CLASS)
        next unless (m = decl.match(PADDING_PROP))

        value = m[1].strip
        next if padding_is_card_budget?(value)

        @tally["card_padding"] << "#{rel}:#{line_no} #{value}"
      end
    end

    def padding_is_card_budget?(value)
      return true if value.start_with?("var(")

      parts = value.scan(/[\d.]+(?:px|rem|em)/)
      return false if parts.empty?

      parts.all? { |part| part == "24px" || part == "1.5rem" }
    end

    # This replaces a check that read design_rules.touch.target_min_px and
    # failed if it was under 44 — the law measured against a constant, with no
    # stylesheet involved. It could not have caught a single real defect: the
    # only way to fail it was to edit the rule file, and the rule file is what
    # it was quoting. What matters is whether the token the family sizes its
    # controls from actually meets the floor the law sets.
    def check_tap_token
      floor = @design.dig("layout_rules", "touch", "target_min_px").to_i
      return if floor <= 0

      source = File.read(token_path("_dialect_tokens.scss"))
      %w[--tap-min --bar-height].each do |name|
        value = source[/#{Regexp.escape(name)}\s*:\s*(\d+)px\s*;/, 1]
        if value.nil?
          @result.warn("css_constitution touch: #{name} is not declared in _dialect_tokens.scss")
          next
        end
        next if value.to_i >= floor

        @result.fail("css_constitution touch: #{name} is #{value}px, under design_rules " \
                     "layout_rules.touch.target_min_px #{floor}px")
      end
    end
  end
end

