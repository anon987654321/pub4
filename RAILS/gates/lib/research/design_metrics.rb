# frozen_string_literal: true

require "yaml"
require_relative "../../../../OPENBSD/lib/gate_result"
require_relative "../../../../OPENBSD/lib/deploy_inventory"
require_relative "../../../tools/crawl_support"
require_relative "../../support/design_metrics"

module Deploy
  # P2: measure design_rules.yml (type, contrast, touch, spacing, measure)
  # against tokens + SCSS source. Optional live browser hit-targets when
  # DESIGN_METRICS_BROWSER=1 and Chrome/Selenium are available.
  class DesignMetricsGate
    ROOT = File.expand_path("../../../..", __dir__)
    RAILS = File.join(ROOT, "RAILS")
    MASTER_RULES = File.join(ROOT, "MASTER", "data", "rules.yml")
    TOKENS = File.join(RAILS, "shared", "design_tokens.yml")
    APPS = %w[brgen amber bsdports shared].freeze

    # Critical interactive CSS roots (Fitts / touch).
    TOUCH_FOCUS = {
      "brgen" => %w[
        app/assets/stylesheets/_forms.scss
        app/assets/stylesheets/_nav.scss
        app/assets/stylesheets/_marketplace.scss
        app/assets/stylesheets/_posts.scss
        app/assets/stylesheets/_dating_actions.scss
        app/assets/stylesheets/_channels.scss
        app/assets/stylesheets/_live.scss
      ],
      "amber" => %w[
        app/assets/stylesheets/_jsfiddle_chrome.scss
      ],
      "bsdports" => %w[
        app/assets/stylesheets/application.scss
      ],
    }.freeze

    def self.run
      new.run
    end

    def run
      @result = GateResult.new
      unless File.file?(MASTER_RULES)
        @result.fail("design_metrics: missing MASTER/data/rules.yml")
        return @result
      end
      @rules = (YAML.safe_load_file(MASTER_RULES, aliases: true) || {})["design_rules"] || {}
      @tokens = File.file?(TOKENS) ? YAML.safe_load_file(TOKENS) : {}

      check_rules_floor
      check_token_type_and_measure
      check_token_contrast
      check_touch_targets
      check_line_height_and_body
      check_spacing_rhythm
      check_type_scale_budget
      check_mobile_input_size
      check_heading_hierarchy
      check_weight_delta
      check_font_families
      check_lowercase_tracking
      check_palette_roles
      optional_browser_hit_targets
      @result
    end

    private

    # The whole source tree, engines included. The sampled lists above predate
    # brgen's verticals becoming mountable engines and reach none of them; the
    # checks below are new, so they start with the real set.
    def source_stylesheets
      @source_stylesheets ||= APPS.flat_map do |app|
        roots = [File.join(RAILS, app, "app/assets/stylesheets")]
        roots.concat(Dir.glob(File.join(RAILS, app, "engines/*/app/assets/stylesheets")))
        roots.flat_map { |r| Dir.glob(File.join(r, "**/*.scss")) }
      end.uniq.sort
    end

    # px for a font-size value, resolving the --text-* ladder from _tokens.scss
    # rather than restating it, so the gate cannot disagree with the tokens.
    def type_ladder
      @type_ladder ||= begin
        path = File.join(RAILS, "shared/app/assets/stylesheets/_tokens.scss")
        read_css(path).scan(/(--text-[\w-]+)\s*:\s*([\d.]+)rem\s*;/)
                      .to_h { |name, rem| [name, rem.to_f * 16] }
      end
    end

    def font_size_px(value)
      v = value.to_s.strip
      if (name = v[/--text-[\w-]+/])
        return type_ladder[name]
      end
      return Regexp.last_match(1).to_f * 16 if v =~ /\A([\d.]+)rem\b/
      return Regexp.last_match(1).to_f if v =~ /\A([\d.]+)px\b/

      nil
    end

    # Yields [selector_line, block_body, line_number] for each innermost rule.
    def each_rule(body)
      lines = body.lines
      opens = []
      lines.each_with_index do |line, index|
        line.each_char do |char|
          if char == "{"
            opens << [index, false]
            opens[0..-2].each { |frame| frame[1] = true }
            next
          end
          next unless char == "}"

          start, nested = opens.pop
          next if start.nil? || nested

          yield lines[start].to_s.strip, lines[start..index].join, start + 1
        end
      end
    end

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

    # ultraminimalism.color.max_palette_roles — the number of *roles* the palette
    # carries, not the number of hexes. accent/danger/success/warning/info is the
    # set that paints meaning; bg/surface/text/border are structure.
    ROLE_TOKENS = %w[accent danger success warning info].freeze

    def check_palette_roles
      max_roles = @rules.dig("ultraminimalism", "color", "max_palette_roles").to_i
      return if max_roles <= 0

      dialect = @tokens["social"] || {}
      roles = ROLE_TOKENS.select { |r| dialect.keys.any? { |k| k.to_s.match?(/\A#{r}(_|\z)/) } }
      return if roles.size <= max_roles

      @result.fail(
        "design_metrics palette: social dialect carries #{roles.size} colour roles " \
        "(#{roles.join(', ')}) over max_palette_roles #{max_roles} — value and spacing " \
        "should carry what a colour is being asked to", severity: :soft
      )
    end

    def check_rules_floor
      touch = @rules.dig("layout_rules", "touch", "target_min_px").to_i
      @result.fail("design_metrics: touch.target_min_px missing/invalid") if touch < 44
      body_min = @rules.dig("typography", "accessibility", "body_min_px").to_i
      @result.fail("design_metrics: body_min_px missing") if body_min < 16
      @result.warn("design_metrics: design_rules loaded (touch≥#{touch}px body≥#{body_min}px)")
    end

    def check_token_type_and_measure
      chrome = @tokens["shared_chrome"] || {}
      body = chrome["font_size_body"]
      if body
        px = DesignMetrics.to_px(body) || (body == "1rem" ? 16.0 : nil)
        min = @rules.dig("typography", "accessibility", "body_min_px").to_f
        if px && px + 0.01 < min
          @result.fail("design_metrics type: shared_chrome.font_size_body #{body} (#{px}px) < body_min_px #{min}", severity: :hard)
        end
      else
        @result.fail("design_metrics type: shared_chrome.font_size_body missing", severity: :soft)
      end

      measure = chrome["measure_body"]
      if measure && (m = measure.to_s[/\A([\d.]+)ch\z/, 1])
        ch = m.to_f
        min_ch = @rules.dig("typography", "line_length", "min_ch").to_f
        max_ch = @rules.dig("typography", "line_length", "max_ch").to_f
        if ch < min_ch || ch > max_ch
          @result.fail(
            "design_metrics measure: measure_body #{measure} outside #{min_ch}–#{max_ch}ch (principle=hierarchy)",
            severity: :hard
          )
        end
      else
        @result.fail("design_metrics measure: shared_chrome.measure_body missing (prefer 66ch)", severity: :soft)
      end

      # Prose max-width in ch should appear in product CSS (marketplace/posts).
      sample = read_css(File.join(RAILS, "brgen/app/assets/stylesheets/_marketplace.scss")) +
               read_css(File.join(RAILS, "brgen/app/assets/stylesheets/_posts.scss"))
      chs = DesignMetrics.extract_ch_measures(sample)
      if chs.any?
        bad = chs.reject { |c| c.between?(@rules.dig("typography", "line_length", "min_ch").to_f, @rules.dig("typography", "line_length", "max_ch").to_f) }
        bad.each do |c|
          @result.fail("design_metrics measure: max-width #{c}ch outside ideal range", severity: :soft)
        end
      else
        @result.fail("design_metrics measure: no max-width …ch in marketplace/posts prose", severity: :soft)
      end
    end

    # Enumerate the whole mode-matched fg/bg space per dialect instead of a
    # hand-written list of eight pairs.
    #
    # The old list checked text/bg and text/surface only, and passed — while
    # social.accent/bg sat at 4.37 and `color: var(--accent)` was being used as
    # a text colour in dozens of rules. Anything the author forgets to list is
    # invisible to a list.
    #
    # Severity is deliberately soft here: this enumerates pairings that *could*
    # occur, and a token pair the UI never actually renders is not a defect.
    # RenderedGeometryGate hard-fails the same threshold on pairs it observes rendered,
    # which is the difference between a possibility and a fact.
    def check_token_contrast
      normal_min = @rules.dig("typography", "accessibility", "normal_text_contrast").to_f
      normal_min = 7.0 if normal_min <= 0 # design_rules AAA default

      all_pairs = @tokens.flat_map { |name, dialect| DesignMetrics.token_pairs(name, dialect) } +
                  DesignMetrics.vertical_accent_pairs(@tokens, RAILS)
      if all_pairs.empty?
        @result.fail("design_metrics contrast: no token pairs resolved from design_tokens.yml", severity: :soft)
        return
      end

      # Only measure colours something paints. Reported rather than dropped
      # quietly: a gate that silently stops counting looks identical to one that
      # was fixed, and this file's own history is a warning about exactly the
      # opposite mistake — vertical accents rendering on social chrome with
      # nothing reporting them.
      # Both sides, not just the foreground. brgen_old_light.text/chrome_bg
      # reported 1.26:1 — which reads as catastrophic until you notice
      # --chrome-bg has no var() consumer left, so that pair measures ink on a
      # surface nothing paints. Checking only the foreground kept it, because
      # --text is read everywhere.
      # Read + wins. "Is the property read" is necessary and not sufficient: a
      # dialect can declare a value, the property can be read everywhere, and a
      # later rule at the same specificity can still overwrite it before it
      # reaches a pixel. social.accent does exactly that in all three apps.
      pairs, unpainted = all_pairs.partition do |p|
        DesignMetrics.token_painted?(RAILS, p[:fg_key]) &&
          DesignMetrics.token_painted?(RAILS, p[:bg_key]) &&
          DesignMetrics.token_value_wins?(RAILS, p[:fg_key], p[:fg]) &&
          DesignMetrics.token_value_wins?(RAILS, p[:bg_key], p[:bg])
      end
      if unpainted.any?
        skipped = unpainted.select { |p| p[:ratio] < 4.5 }
        # Name the side that has no reader, not the pair's foreground. Listing
        # fg_key alone printed "text, accent, danger" — tokens painted all over
        # the tree — because their *background* was the dead one, which reads as
        # though the gate had lost track of the palette entirely.
        dead = unpainted.flat_map { |p|
          [p[:fg_key], p[:bg_key]].reject { |k| DesignMetrics.token_painted?(RAILS, k) }
        }.uniq.sort
        # Two different reasons, reported as two. Calling a shadowed token
        # "unread" is the same error this filter was written to stop: --accent is
        # read everywhere and social's value still never lands.
        shadowed = unpainted.flat_map { |p|
          [[p[:fg_key], p[:fg]], [p[:bg_key], p[:bg]]]
            .select { |k, v| DesignMetrics.token_painted?(RAILS, k) && !DesignMetrics.token_value_wins?(RAILS, k, v) }
            .map { |k, v| "#{k}=#{v}" }
        }.uniq.sort
        detail = []
        detail << "unread: #{dead.join(', ')}" if dead.any?
        detail << "overridden: #{shadowed.join(', ')}" if shadowed.any?
        @result.warn(
          "design_metrics contrast: skipped #{unpainted.size} pair(s) whose colour never reaches a pixel " \
          "(#{skipped.size} of them below AA) — #{detail.join(' | ')}"
        )
      end
      if pairs.empty?
        @result.fail("design_metrics contrast: every token pair is unread — the palette paints nothing",
                     severity: :soft)
        return
      end

      below_aa = pairs.select { |p| p[:ratio] < 4.5 }
      below_aaa = pairs.select { |p| p[:ratio] >= 4.5 && p[:ratio] < normal_min }

      below_aa.sort_by { |p| p[:ratio] }.each do |pair|
        suggestion = DesignMetrics.suggest_contrast_fix(pair[:fg], pair[:bg], 4.5)
        hint = suggestion ? " — #{pair[:fg_key]} #{suggestion[:hex]} would reach #{suggestion[:ratio]}" : ""
        @result.fail(
          "design_metrics contrast: #{pair[:label]} #{pair[:fg]} on #{pair[:bg]} = #{pair[:ratio]} < 4.5 (WCAG AA)" \
          "#{hint} principle=accessibility",
          severity: :soft
        )
      end

      if below_aaa.any?
        @result.warn(
          "design_metrics contrast: #{below_aaa.size} pair(s) between 4.5 and the design_rules AAA target " \
          "#{normal_min} — #{below_aaa.sort_by { |p| p[:ratio] }.first(3).map { |p| "#{p[:label]}=#{p[:ratio]}" }.join(', ')}"
        )
      end
      @result.warn("design_metrics contrast: enumerated #{pairs.size} mode-matched token pairs " \
                   "across #{@tokens.keys.size} dialects (#{below_aa.size} below AA)")
      judge_contrast_budget(below_aa.size, below_aaa.size)
    end

    # Soft failures are warnings unless GATE_STRICT_SOFT is set, so 30 pairs under
    # WCAG AA sat under a green line indefinitely. A ceiling makes the number
    # monotone without going red on arrival — the same trade constitutional_budget
    # and css_budget make.
    def judge_contrast_budget(below_aa, below_aaa)
      budget = contrast_budget
      return @result.warn("design_metrics contrast: no ceiling recorded in css_budget.yml") if budget.empty?

      {
        "contrast_below_aa" => below_aa,
        "contrast_below_aaa" => below_aaa,
      }.each do |key, count|
        ceiling = budget[key]
        next if ceiling.nil?

        if count > ceiling
          @result.fail("design_metrics #{key}: #{count} exceeds ceiling #{ceiling} (+#{count - ceiling}) — " \
                       "raise the contrast, or record a new ceiling with a reason")
        elsif count < ceiling
          @result.warn("design_metrics #{key}: #{count}, under its #{ceiling} ceiling (-#{ceiling - count})")
        end
      end
    end

    def contrast_budget
      path = File.expand_path("../../data/css_budget.yml", __dir__)
      (YAML.safe_load_file(path)&.dig("rules") || {}).slice("contrast_below_aa", "contrast_below_aaa")
    rescue StandardError => e
      warn "design_metrics: rules unreadable (#{e.class}) — gate runs unbudgeted"
      {}
    end

    def check_touch_targets
      min_px = @rules.dig("layout_rules", "touch", "target_min_px").to_f
      css_map = {}
      TOUCH_FOCUS.each do |app, rels|
        rels.each do |rel|
          path = File.join(RAILS, app, rel)
          next unless File.file?(path)

          css_map[path] = File.read(path)
        end
      end

      # Hard: forms/buttons in brgen declare ≥44
      forms = File.join(RAILS, "brgen/app/assets/stylesheets/_forms.scss")
      if File.file?(forms)
        heights = DesignMetrics.extract_min_heights(File.read(forms))
        unless heights.any? { |h| h + 0.01 >= min_px }
          @result.fail("design_metrics touch: _forms.scss missing min-height ≥ #{min_px.to_i}px (principle=fitts_law)", severity: :hard)
        end
      end

      # Interactive coverage across product CSS
      DesignMetrics.interactive_touch_coverage(css_map, min_px: min_px).each do |row|
        next if row[:covered]

        @result.fail(
          "design_metrics touch: #{row[:label]} lacks min-height ≥ #{min_px.to_i}px in #{row[:paths].map { |p| p.sub(RAILS + '/', '') }.join(', ')} (principle=fitts_law)",
          severity: :hard
        )
      end

      # Flag explicit sub-44 min-heights on interactive-looking rules (soft if not primary)
      css_map.each do |path, body|
        body.scan(/min-height\s*:\s*([\d.]+)px/i).flatten.each do |raw|
          h = raw.to_f
          next if h + 0.01 >= min_px
          next if h < 8 # decorative

          # Only hard-fail if on a line with btn/tab/action context within ±2 lines — keep soft for now
          @result.fail(
            "design_metrics touch: #{path.sub(RAILS + '/', '')} min-height #{h.to_i}px < #{min_px.to_i}px",
            severity: :soft
          )
        end
      end
    end

    def check_line_height_and_body
      body_acc = @rules.dig("typography", "line_height", "body_accessibility_min").to_f
      body_min = @rules.dig("typography", "line_height", "body_min").to_f
      files = %w[
        brgen/app/assets/stylesheets/_posts.scss
        brgen/app/assets/stylesheets/_nav.scss
        brgen/app/assets/stylesheets/_forms.scss
        brgen/app/assets/stylesheets/_live.scss
        shared/app/assets/stylesheets/_minimal.scss
      ]
      files.each do |rel|
        path = File.join(RAILS, rel)
        next unless File.file?(path)

        lhs = DesignMetrics.extract_line_heights(File.read(path))
        lhs.each do |lh|
          if lh + 0.001 < body_min
            @result.fail("design_metrics line-height: #{rel} has #{lh} < body_min #{body_min} (principle=accessibility)", severity: :hard)
          elsif lh + 0.001 < body_acc
            @result.fail("design_metrics line-height: #{rel} has #{lh} < accessibility_min #{body_acc} (principle=accessibility)", severity: :soft)
          end
        end
      end
    end

    # design_rules.yml declares the spacing scale twice and the two disagree:
    #
    #   pixel_perfection.eight_px_rhythm     0 4 8 12 16 20 24 32 40 48 64 96
    #   layout_rules.grid.allowed_spacing_px   4 8    16    24 32    48 64
    #
    # This gate read the second, css_constitution's rhythm_allowlist reads the
    # first, so two gates enforced different rules out of one law and 12px and
    # 20px were reported off-scale here while passing there. eight_px_rhythm is
    # the one FINAL_TODO's contract header quotes as the 8px rhythm, so it wins;
    # the grid list stays as the fallback rather than being deleted, since it
    # also carries columns and base_unit_px that nothing else supplies.
    def check_spacing_rhythm
      allowed = Array(@rules.dig("pixel_perfection", "eight_px_rhythm")).map(&:to_i)
      allowed = Array(@rules.dig("layout_rules", "grid", "allowed_spacing_px")).map(&:to_i) if allowed.empty?
      base = @rules.dig("layout_rules", "grid", "base_unit_px").to_i
      base = 8 if base <= 0
      allowed = [4, 8, 16, 24, 32, 48, 64] if allowed.empty?

      samples = %w[
        brgen/app/assets/stylesheets/_marketplace.scss
        brgen/app/assets/stylesheets/_live.scss
        shared/app/assets/stylesheets/_minimal.scss
      ]
      off = []
      samples.each do |rel|
        path = File.join(RAILS, rel)
        next unless File.file?(path)

        DesignMetrics.extract_spacing_px(File.read(path)).each do |px|
          # ignore fractional rem noise; round to nearest px
          r = px.round
          next if r > 128 # section heroes

          off << [rel, r] if DesignMetrics.off_rhythm?(r, allowed: allowed, base: base)
        end
      end
      # Cap soft noise
      off.uniq.first(12).each do |rel, px|
        @result.fail("design_metrics rhythm: #{rel} spacing #{px}px not in 8px scale (principle=rhythm)", severity: :soft)
      end
    end

    def check_type_scale_budget
      max_sizes = @rules.dig("typography", "hierarchy", "max_font_sizes").to_i
      max_sizes = 8 if max_sizes <= 0
      chrome = @tokens["shared_chrome"] || {}
      sizes = %w[font_size_meta font_size_body font_size_title font_size_display].filter_map do |k|
        DesignMetrics.to_px(chrome[k]) if chrome[k]
      end
      if sizes.uniq.size > max_sizes
        @result.fail("design_metrics type_scale: shared_chrome has #{sizes.uniq.size} sizes > max #{max_sizes}", severity: :soft)
      end

      # Scan brgen SCSS for one-off px font sizes
      inventory = []
      Dir.glob(File.join(RAILS, "brgen/app/assets/stylesheets/**/*.scss")).each do |path|
        next if path.include?("/builds/")

        inventory.concat(DesignMetrics.extract_font_sizes_px(File.read(path)))
      end
      uniq = inventory.map(&:round).uniq
      if uniq.size > max_sizes + 6 # allow some responsive noise beyond token set
        @result.fail(
          "design_metrics type_scale: brgen SCSS uses #{uniq.size} distinct px sizes (budget ~#{max_sizes + 6}) principle=hierarchy",
          severity: :soft
        )
      end
    end

    def optional_browser_hit_targets
      return unless %w[1 true yes on].include?(ENV["DESIGN_METRICS_BROWSER"].to_s.strip.downcase)

      begin
        require "selenium-webdriver"
      rescue LoadError
        @result.warn("design_metrics browser: selenium-webdriver not loaded — skip live hit targets")
        return
      end

      inventory = Inventory.new(root: ROOT).apps.find { |a| a.name == "brgen" }
      unless inventory && CrawlSupport.port_open?("127.0.0.1", inventory.port)
        @result.skipped_live("design_metrics browser: brgen port closed — skip live hit targets")
        return
      end

      min_px = @rules.dig("layout_rules", "touch", "target_min_px").to_i
      probes = [
        { host: "brgen.no", path: "/", selector: ".tab-item, .compose-btn, a.tab-item" },
        { host: "markedsplass.brgen.no", path: "/", selector: "#navBar a, .deal-fav, .btn" },
        { host: "brgen.no", path: "/live", selector: ".feed-action, .btn, .live-compose input[type=submit]" },
      ]

      options = Selenium::WebDriver::Chrome::Options.new
      options.add_argument("--headless=new")
      options.add_argument("--disable-gpu")
      options.add_argument("--window-size=390,844")
      driver = nil
      begin
        driver = Selenium::WebDriver.for(:chrome, options: options)
        probes.each do |probe|
          # selenium can't set Host easily — probe apex paths only.
          next if probe[:host].to_s.include?("markedsplass")

          begin
            driver.navigate.to("http://127.0.0.1:#{inventory.port}#{probe[:path]}")
            els = driver.find_elements(css: probe[:selector])
            if els.empty?
              @result.fail("design_metrics browser: no elements for #{probe[:selector]} on #{probe[:path]}", severity: :soft)
              next
            end
            els.first(5).each do |el|
              box = el.size
              h = box.height.to_f
              w = box.width.to_f
              next if h < 1 || w < 1

              next unless [h, w].min + 0.5 < min_px

              @result.fail(
                "design_metrics browser: #{probe[:path]} element ~#{w.to_i}×#{h.to_i} < #{min_px}px (principle=fitts_law)",
                severity: :hard
              )
            end
          rescue Selenium::WebDriver::Error::WebDriverError => e
            @result.warn("design_metrics browser: #{probe[:path]} #{e.class}: #{e.message}")
          end
        end
      ensure
        driver&.quit
      end
    end

    def read_css(path)
      File.file?(path) ? File.read(path) : ""
    end
  end
end
