# frozen_string_literal: true

module Deploy
  class DesignMetricsGate
    # Type, as the five source checks that read it: input size, heading
    # hierarchy, the weight ladder, font families and lowercase tracking.
    #
    # Split out of design_metrics.rb when that file passed its length ceiling
    # again. One subject — every one of these reads a font declaration out of
    # the SCSS and judges it against design_rules.yml's typography section —
    # and the largest of the four the gate carries.
    #
    # A module included back into the gate, like ContrastChecks beside it, so
    # it keeps @rules, @result and the private helpers it shares with the
    # other checks: source_stylesheets, each_rule, font_size_px, type_ladder.
    module TypeChecks
      # typography.accessibility.mobile_input_min_px. Not a taste rule: iOS Safari
      # zooms the viewport when a text field smaller than 16px takes focus, and it
      # does not zoom back out. Radios and checkboxes are exempt — they carry no
      # text caret, so nothing triggers the zoom.
      TEXT_ENTRY = /(?:\btextarea\b|\bselect\b|contenteditable|
                      input(?!\s*\[\s*type\s*=\s*["']?(?:radio|checkbox|range|color|file|submit|button|image)))/x

      def check_mobile_input_size
        min_px = @rules.dig("typography", "accessibility", "mobile_input_min_px").to_f
        return if min_px <= 0

        source_stylesheets.each do |path|
          rel = path.sub("#{RAILS}/", "")
          each_rule(read_css(path)) do |selector, block, line_no|
            next unless selector.match?(TEXT_ENTRY)
            next unless (m = block.match(/font-size\s*:\s*([^;]+)/))

            px = font_size_px(m[1])
            next if px.nil? || px >= min_px

            @result.fail(
              "design_metrics mobile_input: #{rel}:#{line_no} #{selector.delete_suffix('{').strip} " \
              "is #{px.to_i}px — iOS Safari zooms the viewport on focus below #{min_px.to_i}px " \
              "(principle=accessibility)", severity: :hard
            )
          end
        end
      end

      # typography.hierarchy: h1/h2/h3 must be a visible multiple of body, and
      # each level a visible multiple of the next. Declared with numbers since the
      # first version of this file and never read, which is how the tree ended up
      # with headings a step apart from their own body text.
      def check_heading_hierarchy
        hierarchy = @rules["typography"]&.dig("hierarchy") || {}
        body = font_size_px("--text-base") || 16.0
        step = hierarchy["min_size_ratio_between_levels"].to_f

        seen = {}
        source_stylesheets.each do |path|
          rel = path.sub("#{RAILS}/", "")
          each_rule(read_css(path)) do |selector, block, line_no|
            level = selector[/\bh([123])\b/, 1]
            next unless level
            next unless (m = block.match(/font-size\s*:\s*([^;]+)/))

            px = font_size_px(m[1])
            next unless px

            seen["h#{level}"] ||= px
            lo = hierarchy["h#{level}_body_min_ratio"].to_f
            hi = hierarchy["h#{level}_body_max_ratio"].to_f
            next unless lo.positive?

            ratio = (px / body).round(2)
            next if ratio >= lo && (hi <= 0 || ratio <= hi)

            @result.fail(
              "design_metrics hierarchy: #{rel}:#{line_no} h#{level} is #{px.to_i}px, #{ratio}x body " \
              "(want #{lo}–#{hi}x) (principle=hierarchy)", severity: :soft
            )
          end
        end

        return unless step.positive?

        [%w[h1 h2], %w[h2 h3]].each do |bigger, smaller|
          next unless seen[bigger] && seen[smaller] && seen[smaller].positive?

          ratio = (seen[bigger] / seen[smaller]).round(2)
          next if ratio >= step

          @result.fail(
            "design_metrics hierarchy: #{bigger} (#{seen[bigger].to_i}px) is only #{ratio}x " \
            "#{smaller} (#{seen[smaller].to_i}px), under min_size_ratio_between_levels #{step}",
            severity: :soft
          )
        end
      end

      # typography.hierarchy.min_weight_delta. The ladder was cut to 400/600/800
      # by hand on 2026-08-09 precisely because 700 sat 100 from 800 and read as
      # one weight. Nothing held that, so this does.
      def check_weight_delta
        delta = @rules.dig("typography", "hierarchy", "min_weight_delta").to_f
        max_weights = @rules.dig("typography", "hierarchy", "max_font_weights").to_i
        return if delta <= 0

        path = File.join(RAILS, "shared/app/assets/stylesheets/_dialect_tokens.scss")
        weights = read_css(path).scan(/--weight-[\w-]+\s*:\s*(\d{3})\s*;/).flatten.map(&:to_i).uniq.sort
        return if weights.size < 2

        if max_weights.positive? && weights.size > max_weights
          @result.fail(
            "design_metrics weights: ladder declares #{weights.size} weights (#{weights.join('/')}) " \
            "over max_font_weights #{max_weights}", severity: :soft
          )
        end

        weights.each_cons(2) do |low, high|
          next if (high - low) >= delta

          @result.fail(
            "design_metrics weights: #{low} and #{high} are #{high - low} apart, under " \
            "min_weight_delta #{delta.to_i} — a step that small does not read (principle=hierarchy)",
            severity: :soft
          )
        end
      end

      # typography.hierarchy.max_font_families, counted per app. Dialect faces are
      # the point of this tree (mono for the CRT surfaces, Caprasimo for amber), so
      # the ceiling is per app rather than per repo, and @font-face blocks are the
      # declaration of a file rather than a choice of family.
      def check_font_families
        max_families = @rules.dig("typography", "hierarchy", "max_font_families").to_i
        return if max_families <= 0

        APPS.each do |app|
          families = Set.new
          source_stylesheets.select { |p| p.include?("/#{app}/") }.each do |path|
            in_face = false
            read_css(path).each_line do |line|
              in_face = true if line.match?(/@font-face/)
              if !in_face && (m = line.match(/font-family\s*:\s*([^;]+)/))
                value = m[1].strip
                next if value.start_with?("var(", "inherit")

                families << value.split(",").first.to_s.strip.delete('"').downcase
              end
              in_face = false if in_face && line.match?(/\A\s*\}/)
            end
          end
          next if families.size <= max_families

          @result.fail(
            "design_metrics families: #{app} names #{families.size} font families " \
            "(#{families.to_a.sort.join(', ')}) over max_font_families #{max_families}", severity: :soft
          )
        end
      end

      # typography.letter_spacing.lowercase_body_should_letterspace is false.
      # Tracking opens up all-caps, where the counters close; on lowercase prose it
      # breaks the word shape a reader matches against.
      def check_lowercase_tracking
        return if @rules.dig("typography", "letter_spacing", "lowercase_body_should_letterspace")

        source_stylesheets.each do |path|
          rel = path.sub("#{RAILS}/", "")
          each_rule(read_css(path)) do |selector, block, line_no|
            next if block.match?(/text-transform\s*:\s*uppercase/)
            next unless (m = block.match(/letter-spacing\s*:\s*(-?[\d.]+)em/))

            tracking = m[1].to_f
            next unless tracking > 0.01

            @result.fail(
              "design_metrics tracking: #{rel}:#{line_no} #{selector.delete_suffix('{').strip} " \
              "letter-spaces lowercase text at #{tracking}em (principle=legibility)", severity: :soft
            )
          end
        end
      end
    end
  end
end
