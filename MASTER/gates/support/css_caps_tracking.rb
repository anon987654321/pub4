# frozen_string_literal: true

module Deploy
  # typography.letter_spacing.all_caps_min_em, read by CssConstitutionGate. An
  # all-caps label without tracking closes its counters up and reads as a solid
  # block; the law puts the floor at 0.05em and the ceiling at 0.15em.
  #
  # It reached zero in the 2026-08-09 typography pass, so it is a hard check
  # rather than a ceiling. It reads the gate's @design, @result, token_path and
  # strip_comments.
  module CssCapsTracking
    UPPERCASE = /text-transform\s*:\s*uppercase/
    LETTER_SPACING = /letter-spacing\s*:\s*(-?[\d.]+)em/

    private

    def check_caps_tracking(rel, body)
      floor = @design.dig("typography", "letter_spacing", "all_caps_min_em").to_f
      ceiling = @design.dig("typography", "letter_spacing", "all_caps_max_em").to_f
      return if floor.zero?

      each_declaration_block(strip_comments(body)) do |block, line_no|
        next unless block.match?(UPPERCASE)

        tracking = block[LETTER_SPACING, 1] || tracking_from_token(block)
        if tracking.nil?
          @result.fail("css_constitution caps_tracking: #{rel}:#{line_no} sets uppercase with no " \
                       "letter-spacing (floor #{floor}em)")
        elsif tracking.to_f < floor
          @result.fail("css_constitution caps_tracking: #{rel}:#{line_no} tracks uppercase at " \
                       "#{tracking}em, below the #{floor}em floor")
        elsif ceiling.positive? && tracking.to_f > ceiling
          @result.fail("css_constitution caps_tracking: #{rel}:#{line_no} tracks uppercase at " \
                       "#{tracking}em, above the #{ceiling}em ceiling")
        end
      end
    end

    # name -> em, read from the file that declares the tokens. Without this the
    # check above sees var(--tracking-wide) as "no letter-spacing at all" and
    # fails every rule that correctly uses the token instead of a literal.
    def tracking_ladder
      @tracking_ladder ||= begin
        file = token_path("_typography.scss")
        body = File.file?(file) ? File.read(file) : ""
        body.scan(/(--tracking-[\w-]+)\s*:\s*(-?[\d.]+)em\s*;/).to_h { |n, v| [ n, v.to_f ] }
      end
    end

    # The em a var(--tracking-*) resolves to, as a string so the caller's numeric
    # comparisons are unchanged. An unknown token returns nil and is reported as
    # untracked, which is the safe direction: a name nothing declares sets nothing.
    def tracking_from_token(block)
      name = block[/letter-spacing\s*:\s*var\(\s*(--tracking-[\w-]+)/, 1] or return nil
      value = tracking_ladder[name] or return nil

      value.to_s
    end

    # Yields each *innermost* `{ … }` declaration block with the 1-based line its
    # selector opens on. Nesting depth is tracked rather than assumed, because
    # this tree writes SCSS nested inside @media and body.vertical-* wrappers —
    # and only the innermost block is a rule. Yielding enclosing blocks too would
    # let a sibling's letter-spacing vouch for an untracked uppercase rule.
    def each_declaration_block(body)
      lines = body.lines
      opens = []
      lines.each_with_index do |line, index|
        line.each_char do |char|
          if char == "{"
            opens << [index, false]
            # Mark every enclosing block as having a child.
            opens[0..-2].each { |frame| frame[1] = true }
            next
          end
          next unless char == "}"

          start, nested = opens.pop
          next if start.nil? || nested

          yield lines[start..index].join, start + 1
        end
      end
    end
  end
end
