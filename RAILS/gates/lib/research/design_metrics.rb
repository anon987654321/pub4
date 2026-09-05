# frozen_string_literal: true

require "yaml"
require_relative "../../support/design_metrics_contrast_checks"
require_relative "../../../../OPENBSD/lib/gate_result"
require_relative "../../../../OPENBSD/lib/deploy_inventory"
require_relative "../../../tools/crawl_support"
require_relative "../../support/design_metrics"
require_relative "../../../shared/lib/pub4/master_design"

module Deploy
  # P2: measure design_rules.yml (type, contrast, touch, spacing, measure)
  # against tokens + SCSS source. Optional live browser hit-targets when
  # DESIGN_METRICS_BROWSER=1 and Chrome/Selenium are available.
  class DesignMetricsGate
    include ContrastChecks

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
      @rules = Pub4::MasterDesign.blocks(MASTER_RULES)
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

      # prefer_monochrome_with_one_accent is the same budget in words. Reading
      # it here is what stops the key looking enforced while only its neighbour
      # is. The numeric cap is the check.
      @rules.dig("ultraminimalism", "color", "prefer_monochrome_with_one_accent")

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
      recommended = @rules.dig("layout_rules", "touch", "target_recommended_px").to_i
      @result.fail("design_metrics: touch.target_min_px missing/invalid") if touch < 44
      @result.fail("design_metrics: touch.target_recommended_px missing/invalid") if recommended < touch
      body_min = @rules.dig("typography", "accessibility", "body_min_px").to_i
      @result.fail("design_metrics: body_min_px missing") if body_min < 16
      gap = @rules.dig("layout_rules", "whitespace", "gap_over_margin")
      @result.fail("design_metrics: whitespace.gap_over_margin missing") if gap.nil?
      card = @rules.dig("ultraminimalism", "negative_space", "card_padding_px").to_i
      @result.fail("design_metrics: card_padding_px missing/invalid") if card <= 0
      columns = @rules.dig("layout_rules", "grid", "columns").to_i
      @result.fail("design_metrics: grid.columns missing/invalid") if columns <= 0
      para = @rules.dig("layout_rules", "whitespace", "paragraph_margin_em").to_f
      @result.fail("design_metrics: paragraph_margin_em missing/invalid") if para <= 0
      sec_min = @rules.dig("layout_rules", "whitespace", "section_padding_min_rem").to_f
      sec_max = @rules.dig("layout_rules", "whitespace", "section_padding_max_rem").to_f
      @result.fail("design_metrics: section_padding missing/invalid") if sec_min <= 0 || sec_max < sec_min
      sidebar = @rules.dig("layout_rules", "proportion", "split_sidebar_ratio").to_f
      main = @rules.dig("layout_rules", "proportion", "split_main_ratio").to_f
      @result.fail("design_metrics: split ratios missing/invalid") if sidebar <= 0 || (main + sidebar - 1.0).abs > 0.02
      visible = @rules.dig("ultraminimalism", "swiss_style", "visible_grid_optional")
      @result.fail("design_metrics: visible_grid_optional missing") if visible.nil?
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
        { host: "brgen.no", path: "/nearby", selector: ".btn, .nearby-locate-actions button" },
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
