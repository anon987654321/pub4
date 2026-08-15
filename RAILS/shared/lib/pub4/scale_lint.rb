# frozen_string_literal: true

require "yaml"

module Pub4
  # Ratchet: every spacing, line-height, radius and weight literal in the family's
  # stylesheets must land on a declared step.
  #
  # This is the axis BreakpointLint's header lists as already single-sourced and
  # is not. Colour is single-sourced, motion is single-sourced, elevation is
  # single-sourced, viewport is single-sourced since breakpoint_lint. Rhythm was
  # never measured, and it drifted the way an unmeasured axis always does:
  # 539 spacing literals over 93 distinct values, and 13 distinct line-heights
  # for what is one body-text rhythm (1.5, 1.55, 1.45, 1.4, 1.3, 1.25, 1.2, 1.15,
  # 1.6, 1.7 …), measured 2026-08-15.
  #
  # The nearest prior art is the stylelint ecosystem — `stylelint-scales`
  # (numeric scales per property, with autofix to the nearest allowed step),
  # `rhythmguard` (token-or-scale enforcement for spacing/radius/type), and
  # `stylelint-a11y`'s line-height-is-vertical-rhythmed. None of them run here:
  # this tree has no Node in its check path and its lints are Ruby over source.
  # So the rule families are reimplemented, not the tools.
  #
  # Five kinds, because they fail differently:
  #
  #   off_scale_space       a padding/margin/gap step nothing else in the family
  #                         uses. Two of these next to each other read as a
  #                         mistake even when neither is wrong alone.
  #   off_scale_line_height a body rhythm invented at the call site. This is the
  #                         one that shows as "the page looks unsettled": a
  #                         paragraph at 1.45 beside one at 1.55 is a half-pixel
  #                         of drift per line that accumulates down the column.
  #   absolute_line_height  `line-height: 28px`. It does not inherit — any child
  #                         at another font-size gets 28px anyway, which is the
  #                         defect stylelint-a11y's rule exists for, and it is
  #                         worse here because brgen's root is 18px.
  #   off_scale_radius      a corner nothing else in the family has.
  #   off_scale_font_weight a weight the loaded faces may not even have, which
  #                         the browser then synthesises.
  #
  # Same contract as breakpoint_lint and chrome_i18n_lint: a baseline per kind,
  # never raised to silence a new finding. Opt out one line with `// scale: ok`
  # on it or the line above.
  module ScaleLint
    RAILS_ROOT = File.expand_path("../../..", __dir__)
    TOKENS = File.join(RAILS_ROOT, "shared", "design_tokens.yml")
    OPT_OUT = "scale: ok"

    SKIP = %r{/(node_modules|vendor|builds|public/assets|tmp)/}

    SPACE_PROPS = %w[
      padding padding-top padding-right padding-bottom padding-left
      padding-inline padding-block padding-inline-start padding-inline-end
      margin margin-top margin-right margin-bottom margin-left
      margin-inline margin-block
      gap row-gap column-gap
    ].freeze

    # Keywords and shapes that are not a step on any scale: they are either a
    # computed value the lint cannot resolve, or an explicit escape.
    UNMEASURABLE = /\A(auto|inherit|initial|unset|revert|normal|none|0|0px|0rem|0em|0%)\z/i

    Finding = Struct.new(:file, :line, :kind, :value, :property)

    module_function

    def tokens = @tokens ||= YAML.safe_load_file(TOKENS)

    def scale = @scale ||= tokens.fetch("scale")

    # rem is normalised at 16, not at brgen's 18. A scale step is a design
    # decision expressed in one unit or the other, and 0.75rem and 12px are the
    # same decision written twice -- that is exactly what design_tokens.yml says
    # when it explains why chrome_inset is absolute. What brgen's root does to
    # the rendered pixel is a different question from whether the author picked
    # a step off the scale, and only the second one is answerable from source.
    def to_px(value, unit)
      case unit
      when "rem", "em" then value.to_f * 16
      when "px", "" then value.to_f
      end
    end

    def stylesheets
      @stylesheets ||= (
        Dir.glob(File.join(RAILS_ROOT, "*/app/assets/stylesheets/**/*.{scss,css}")) +
        Dir.glob(File.join(RAILS_ROOT, "*/engines/*/app/assets/stylesheets/**/*.{scss,css}")) +
        Dir.glob(File.join(RAILS_ROOT, "shared/app/assets/stylesheets/**/*.{scss,css}"))
      ).uniq.sort.reject { |path| path.match?(SKIP) }
    end

    # Comments blanked, line numbering preserved. Same reasoning as
    # breakpoint_lint: a paragraph explaining why a value was changed contains
    # the value, and a lint that reports its own documentation gets the
    # documentation deleted.
    def source_lines(path)
      raw = File.read(path, encoding: "UTF-8")
      raw = raw.gsub(%r{/\*.*?\*/}m) { |block| block.gsub(/[^\n]/, " ") }
      raw.gsub(%r{//[^\n]*}) { |line| " " * line.length }.lines
    end

    def opted_out?(lines, index)
      [lines[index], index.positive? ? lines[index - 1] : nil]
        .compact.any? { |line| line.include?(OPT_OUT) }
    end

    # Everything a build computes rather than an author choosing: var(), calc(),
    # clamp(), min(), max(), env() and SCSS interpolation. Blanked before
    # tokenising, so `calc(var(--x) + 3px)` contributes nothing rather than
    # contributing "3px" as if someone had typed it as a step.
    def strip_computed(value)
      out = value.dup
      6.times { out = out.gsub(/\b(?:var|calc|clamp|min|max|env|minmax|repeat)\([^()]*\)/, " ") }
      out.gsub(/\$[\w-]+/, " ").gsub(/#\{[^}]*\}/, " ").gsub(/!important/, " ")
    end

    LENGTH = /\A(-?[\d.]+)(px|rem|em)?\z/

    def steps(value)
      strip_computed(value).split(/[\s,\/]+/).reject(&:empty?)
    end

    # A declaration is on-scale when every length it names is a declared step.
    # Negative values are checked by magnitude: -1px is a hairline pull, and
    # whether it is on the scale is the same question as whether 1px is.
    def off_scale_lengths(value, allowed_px)
      steps(value).filter_map do |step|
        next if step.match?(UNMEASURABLE)
        next unless (m = step.match(LENGTH))

        px = to_px(m[1], m[2].to_s)
        next if px.nil?

        step unless allowed_px.include?(px.abs.round(3))
      end
    end

    def space_px = @space_px ||= scale.fetch("space_px").map { |v| Float(v) }

    def radius_px = @radius_px ||= scale.fetch("radius_px").map { |v| Float(v) }

    def line_heights = @line_heights ||= scale.fetch("line_height").map { |v| Float(v) }

    def font_weights = @font_weights ||= scale.fetch("font_weight").map { |v| Integer(v) }

    DECLARATION = /(?<prop>[-a-z]+)\s*:\s*(?<value>[^;{}]+)[;}]/

    def findings
      stylesheets.flat_map do |path|
        lines = source_lines(path)
        lines.each_with_index.flat_map do |line, index|
          next [] if opted_out?(lines, index)

          line.to_enum(:scan, DECLARATION).map { Regexp.last_match }
              .flat_map { |m| check(rel(path), index + 1, m[:prop], m[:value].strip) }
        end
      end
    end

    def check(file, line, prop, value)
      case prop
      when *SPACE_PROPS
        off_scale_lengths(value, space_px).map { |v| Finding.new(file, line, "off_scale_space", v, prop) }
      when "border-radius"
        check_radius(file, line, prop, value)
      when "line-height"
        check_line_height(file, line, prop, value)
      when "font-weight"
        check_font_weight(file, line, prop, value)
      else
        []
      end
    end

    # A percentage radius is a circle or a pill, not a step -- 50% and 100% are
    # shapes and the scale has nothing to say about them.
    def check_radius(file, line, prop, value)
      return [] if value.include?("%")

      off_scale_lengths(value, radius_px).map { |v| Finding.new(file, line, "off_scale_radius", v, prop) }
    end

    def check_line_height(file, line, prop, value)
      bare = strip_computed(value).strip
      return [] if bare.empty? || bare.match?(UNMEASURABLE)

      if (m = bare.match(/\A(-?[\d.]+)(px|rem|em|%)\z/))
        return [Finding.new(file, line, "absolute_line_height", "#{m[1]}#{m[2]}", prop)]
      end
      return [] unless bare.match?(/\A[\d.]+\z/)
      return [] if line_heights.include?(Float(bare))

      [Finding.new(file, line, "off_scale_line_height", bare, prop)]
    end

    def check_font_weight(file, line, prop, value)
      bare = strip_computed(value).strip
      return [] unless bare.match?(/\A\d+\z/)
      return [] if font_weights.include?(Integer(bare))

      [Finding.new(file, line, "off_scale_font_weight", bare, prop)]
    end

    def rel(path) = path.sub("#{RAILS_ROOT}/", "")

    def counts = findings.group_by(&:kind).transform_values(&:size)

    def baselines = @baselines ||= scale.fetch("baselines")

    # The nearest declared step, for a report that says what to write instead.
    def nearest(finding)
      allowed = case finding.kind
                when "off_scale_space" then space_px
                when "off_scale_radius" then radius_px
                else return nil
                end
      m = finding.value.match(LENGTH) or return nil
      px = to_px(m[1], m[2].to_s).abs
      "#{allowed.min_by { |step| (step - px).abs }.to_i}px"
    end
  end
end
