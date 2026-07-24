# frozen_string_literal: true

require "yaml"
require_relative "../../../OPENBSD/lib/gate_result"
require_relative "../../../OPENBSD/lib/deploy_inventory"
require_relative "../../crawl_support"
require_relative "design_metrics"

module Deploy
  # P2: measure design_rules.yml (type, contrast, touch, spacing, measure)
  # against tokens + SCSS source. Optional live browser hit-targets when
  # DESIGN_METRICS_BROWSER=1 and Chrome/Selenium are available.
  class DesignMetricsGate
    ROOT = File.expand_path("../../..", __dir__)
    RAILS = File.join(ROOT, "RAILS")
    MASTER_RULES = File.join(ROOT, "MASTER", "data", "design_rules.yml")
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
        @result.fail("design_metrics: missing MASTER/data/design_rules.yml")
        return @result
      end
      @rules = YAML.safe_load_file(MASTER_RULES)
      @tokens = File.file?(TOKENS) ? YAML.safe_load_file(TOKENS) : {}

      check_rules_floor
      check_token_type_and_measure
      check_token_contrast
      check_touch_targets
      check_line_height_and_body
      check_spacing_rhythm
      check_type_scale_budget
      optional_browser_hit_targets
      @result
    end

    private

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

    def check_token_contrast
      normal_min = @rules.dig("typography", "accessibility", "normal_text_contrast").to_f
      normal_min = 7.0 if normal_min <= 0 # design_rules AAA default
      pairs = []

      pair_specs = [
        ["social", "text", "bg"],
        ["social", "text", "surface"],
        ["light", "text", "bg"],
        ["brgen_old_light", "text", "bg"],
        ["brgen_old_dark", "text", "bg"],
        ["luxury", "light_text", "light_bg"],
        ["luxury", "dark_text", "dark_bg"],
        ["openbsd_wscons", "text", "bg"],
      ]

      pair_specs.each do |dialect, fg_key, bg_key|
        dialect_data = @tokens[dialect]
        next unless dialect_data.is_a?(Hash)

        fg = dialect_data[fg_key]
        bg = dialect_data[bg_key]
        next unless fg && bg

        ratio = DesignMetrics.contrast_ratio(fg, bg)
        next unless ratio

        label = "#{dialect}.#{fg_key}/#{bg_key}"
        if ratio < 4.5
          @result.fail("design_metrics contrast: #{label} ratio #{ratio} < 4.5 (WCAG AA) principle=accessibility", severity: :hard)
        elsif ratio < normal_min
          @result.fail(
            "design_metrics contrast: #{label} ratio #{ratio} < design_rules #{normal_min} (AAA target) principle=accessibility",
            severity: :soft
          )
        end
        pairs << [label, ratio]
      end
      @result.warn("design_metrics contrast: checked #{pairs.size} token pairs") if pairs.any?
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

    def check_spacing_rhythm
      allowed = Array(@rules.dig("layout_rules", "grid", "allowed_spacing_px")).map(&:to_i)
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
      uniq = inventory.map { |s| s.round }.uniq
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
        @result.warn("design_metrics browser: brgen port closed — skip live hit targets")
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
