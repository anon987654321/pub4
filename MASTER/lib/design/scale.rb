# frozen_string_literal: true

module Master
  module Design
    # The design scale as one set of rules: which declarations it governs, how a
    # value is read (units, computed parts, opt-outs) and what the nearest step
    # is. MASTER/data/tokens.yml#tokens.scale holds the steps.
    #
    # Three readers asked these questions three ways: tools/scale_lint.rb (the
    # ratchet), the EIGHT_PX_RHYTHM and LINE_HEIGHT_ON_SCALE detectors, and
    # AstFixer's snap_to_eight_px_rhythm. The detector allowed any multiple of 4
    # up to 96, the ratchet the declared steps; the transform snapped to multiples
    # of 8, so it turned the 1px hairline the scale allows into 0px and left 52px,
    # which the scale does not allow, as it was. A finding /fix could not clear and
    # a fix the Law did not ask for. Now the three read this.
    #
    # Stdlib only, and the steps are handed in: tools/scale_lint.rb runs on the VPS
    # beside the apps, without MASTER booted.
    class Scale
      SPACE_PROPS = %w[
        padding padding-top padding-right padding-bottom padding-left
        padding-inline padding-block padding-inline-start padding-inline-end
        margin margin-top margin-right margin-bottom margin-left
        margin-inline margin-block
        gap row-gap column-gap
      ].freeze

      # Keywords and shapes that are not a step on any scale: a computed value
      # that cannot be resolved here, or an explicit escape.
      UNMEASURABLE = /\A(auto|inherit|initial|unset|revert|normal|none|0|0px|0rem|0em|0%)\z/i
      LENGTH = /\A(-?[\d.]+)(px|rem|em)?\z/
      DECLARATION = /(?<prop>[-a-z]+)\s*:\s*(?<value>[^;{}]+)[;}]/
      OPT_OUT = "scale: ok"
      COMPUTED = /\b(?:var|calc|clamp|min|max|env|minmax|repeat)\([^()]*\)/

      # rem is normalised at 16, not at brgen's 18. A scale step is a design
      # decision expressed in one unit or the other, and 0.75rem and 12px are the
      # same decision written twice.
      REM_PX = 16.0

      attr_reader :space_px, :line_heights

      def initialize(scale)
        @space_px = scale.fetch("space_px").map { |v| Float(v) }.freeze
        @line_heights = scale.fetch("line_height").map { |v| Float(v) }.freeze
      end

      def self.to_px(value, unit)
        case unit.to_s
        when "rem", "em" then value.to_f * REM_PX
        when "px", "" then value.to_f
        end
      end

      # Everything a build computes rather than an author choosing: var(), calc(),
      # clamp(), min(), max(), env() and SCSS interpolation. Blanked before
      # tokenising, so `calc(var(--x) + 3px)` contributes nothing rather than
      # contributing "3px" as if someone had typed it as a step.
      def self.strip_computed(value)
        out = value.dup
        6.times { out = out.gsub(COMPUTED, " ") }
        out.gsub(/\$[\w-]+/, " ").gsub(/#\{[^}]*\}/, " ").gsub(/!important/, " ")
      end

      def self.steps(value) = strip_computed(value).split(%r{[\s,/]+}).reject(&:empty?)

      # A declaration is on-scale when every length it names is a declared step.
      # Negative values are checked by magnitude: -1px is a hairline pull, and
      # whether it is on the scale is the same question as whether 1px is.
      def off_scale_lengths(value, allowed = space_px)
        self.class.steps(value).filter_map do |step|
          next if step.match?(UNMEASURABLE)
          next unless (m = step.match(LENGTH))

          px = self.class.to_px(m[1], m[2])
          step unless px.nil? || allowed.include?(px.abs.round(3))
        end
      end

      # A tie resolves to the smaller step, the ratchet's long-standing contract.
      def nearest(length, allowed = space_px) = allowed.min_by { |step| [(step - length.abs).abs, step] }

      # A unitless line-height is a step or it is off the scale; a length is an
      # absolute line-height, which does not inherit and has no step to snap to.
      def line_height_kind(value)
        bare = self.class.strip_computed(value).strip
        return if bare.empty? || bare.match?(UNMEASURABLE)
        return :absolute if bare.match?(/\A-?[\d.]+(px|rem|em|%)\z/)
        return unless bare.match?(/\A[\d.]+\z/)

        line_heights.include?(Float(bare)) ? nil : :off_scale
      end

      # The declaration with each off-scale step replaced by the nearest one, in
      # the unit it was written in; anything computed, unmeasurable or absolute is
      # left exactly as written. nil when nothing changes.
      def snap(prop, value)
        snapped = if SPACE_PROPS.include?(prop)
          snap_lengths(value)
        elsif prop == "line-height" && line_height_kind(value) == :off_scale
          value.sub(/[\d.]+/) { |number| format_step(nearest(Float(number), line_heights)) }
        end

        snapped == value ? nil : snapped
      end

      private

      BARE_LENGTH = /(?<![\w.#$-])(-?)(\d*\.?\d+)(px|rem|em)?(?![\w%.])/
      SLOT = /\u0000(\d+)\u0000/

      # Token by token, so a computed part keeps every character it had: each is
      # set aside, the bare lengths snapped, and the parts put back.
      def snap_lengths(value)
        computed = []
        masked = until_stable(value) { |text| text.gsub(COMPUTED) { |part| slot(computed, part) } }
        snapped = masked.gsub(BARE_LENGTH) { snap_length(Regexp.last_match) || Regexp.last_match[0] }
        until_stable(snapped) { |text| text.gsub(SLOT) { computed[Regexp.last_match(1).to_i] } }
      end

      def slot(computed, part)
        computed << part
        "\u0000#{computed.size - 1}\u0000"
      end

      # Inside out: calc(var(--x) + 3px) is one part, and its 3px is not a step.
      def until_stable(text)
        loop do
          after = yield(text)
          return after if after == text

          text = after
        end
      end

      def snap_length(match)
        sign, number, unit = match.captures
        px = self.class.to_px(number, unit)
        return if px.nil? || px.zero? || space_px.include?(px.round(3))

        step = nearest(px)
        relative = %w[rem em].include?(unit)
        "#{sign}#{relative ? format_step(step / REM_PX) : step.to_i}#{unit}"
      end

      def format_step(number) = number == number.to_i ? number.to_i.to_s : number.round(4).to_s.sub(/0+\z/, "")
    end
  end
end
