# frozen_string_literal: true

require "json"
require_relative "../../support/design_metrics/contrast_checks"
require_relative "../../support/design_metrics/type_checks"
require_relative "../../../../OPENBSD/lib/gate_result"
require_relative "../../../../OPENBSD/lib/deploy_inventory"
require_relative "../../../../RAILS/tools/crawl_support"
require_relative "../../support/geometry_probe"
require_relative "../../support/design_metrics"
require_relative "../../../tools/design/master_design"
require_relative "../../../tools/design/scss_rules"

module Deploy
  # P2: measure design_rules.yml (type, contrast, touch, spacing, measure)
  # against tokens + SCSS source. Optional live browser hit-targets when
  # DESIGN_METRICS_BROWSER=1 and Chrome/Selenium are available.
  class DesignMetricsGate
    include ContrastChecks
    include TypeChecks

    ROOT = File.expand_path("../../../..", __dir__)
    RAILS = File.join(ROOT, "RAILS")
    MASTER_RULES = File.join(ROOT, "MASTER", "data", "rules.yml")
    APPS = %w[brgen amber bsdports shared].freeze

    # The component families the sampled checks read, named by the class a
    # selector opens with: each app styles every component from one
    # application.scss, so a sample is the rules for posts and their forms, the
    # feed nav, form controls, marketplace filters and cart, dating's swipe
    # actions or channels, wherever they sit. A rule that only reaches one of
    # these classes from inside another component belongs to that component.
    SAMPLES = {
      posts: /\A(?:\.(?:post[-_]|vote-|comment[-_]|form-wrap|field\b|story-(?:reply|ring)|fedi-follow)|(?:label|input|textarea|select)\b)/,
      nav: /\A\.(?:feed-(?:header|brand-mark|tabs?)|compose-(?:hint|avatar|input|actions?))\b/,
      forms: /\A(?:\.(?:btn|media-btn|char-counter|form-help|advanced-fields|disappearing-settings|compose-box)\b|#comments-section\b)/,
      marketplace: /\A\.(?:marketplace-actions|store-(?:pills|results|filters)|deal-cat|cart-pay-actions|order-(?:chat|returns?)|listing-(?:questions?|answer|facets?|filters?)|variant-|address)/,
      dating_actions: /\A\.swipe-/,
      channels: /\A\.(?:channels?-|roster-|msg-nick|chat-code)/,
    }.freeze

    # Critical interactive CSS (Fitts / touch): a selector sample per app, or
    # nil for the whole stylesheet.
    TOUCH_FOCUS = {
      "brgen" => Regexp.union(SAMPLES.values_at(:forms, :nav, :marketplace, :posts, :dating_actions, :channels)),
      "amber" => /\.jox-logo\b/,
      "bsdports" => nil,
    }.freeze

    def self.run
      new.run
    end

    # Every source check this gate runs, and the number it reports as measured.
    # A list rather than fourteen call lines, so the count cannot drift from the
    # calls the way a hand-typed 13 does.
    SOURCE_CHECKS = %i[
      check_rules_floor check_token_type_and_measure check_token_contrast
      check_touch_targets check_line_height_and_body check_spacing_rhythm
      check_type_scale_budget check_mobile_input_size check_heading_hierarchy
      check_weight_delta check_font_families check_lowercase_tracking
      check_palette_roles
    ].freeze

    def run
      @result = GateResult.new
      unless File.file?(MASTER_RULES)
        @result.fail("design_metrics: missing MASTER/data/rules.yml")
        return @result
      end
      @rules = Operator::MasterDesign.blocks(MASTER_RULES)
      @tokens = Operator::MasterDesign.design_system

      @result.checked!(SOURCE_CHECKS.size)
      SOURCE_CHECKS.each { |check| send(check) }
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
      chs = DesignMetrics.extract_ch_measures(sample_css("brgen", Regexp.union(SAMPLES.values_at(:marketplace, :posts))))
      if chs.any?
        bad = chs.reject { |c| c.between?(@rules.dig("typography", "line_length", "min_ch").to_f, @rules.dig("typography", "line_length", "max_ch").to_f) }
        bad.each do |c|
          @result.fail("design_metrics measure: max-width #{c}ch outside ideal range", severity: :soft)
        end
      else
        @result.fail("design_metrics measure: no max-width …ch in marketplace/posts prose", severity: :soft)
      end
    end

    # The rules of an app's application.scss whose selectors match, as CSS
    # text, or the whole file when the selector is nil.
    def sample_css(app, selector = nil)
      body = read_css(File.join(RAILS, app, "app/assets/stylesheets/application.scss"))
      return body if selector.nil?

      Operator::ScssRules.matching(body, selector).map { |rule| "#{rule.selector} { #{rule.body} }\n" }.join
    end

    def check_touch_targets
      min_px = @rules.dig("layout_rules", "touch", "target_min_px").to_f
      css_map = TOUCH_FOCUS.to_h { |app, selector| ["#{app}/app/assets/stylesheets/application.scss", sample_css(app, selector)] }
                           .reject { |_, body| body.empty? }

      # Hard: forms/buttons in brgen declare ≥44
      unless DesignMetrics.extract_min_heights(sample_css("brgen", SAMPLES[:forms])).any? { |h| h + 0.01 >= min_px }
        @result.fail("design_metrics touch: brgen form controls missing min-height ≥ #{min_px.to_i}px (principle=fitts_law)", severity: :hard)
      end

      # Interactive coverage across product CSS
      DesignMetrics.interactive_touch_coverage(css_map, min_px: min_px).each do |row|
        next if row[:covered]

        @result.fail(
          "design_metrics touch: #{row[:label]} lacks min-height ≥ #{min_px.to_i}px in #{row[:paths].join(', ')} (principle=fitts_law)",
          severity: :hard
        )
      end

      # Flag explicit sub-44 min-heights on interactive-looking rules (soft if not primary)
      css_map.each do |rel, body|
        body.scan(/min-height\s*:\s*([\d.]+)px/i).flatten.each do |raw|
          h = raw.to_f
          next if h + 0.01 >= min_px
          next if h < 8 # decorative

          @result.fail("design_metrics touch: #{rel} min-height #{h.to_i}px < #{min_px.to_i}px", severity: :soft)
        end
      end
    end

    def check_line_height_and_body
      body_acc = @rules.dig("typography", "line_height", "body_accessibility_min").to_f
      body_min = @rules.dig("typography", "line_height", "body_min").to_f
      samples = {
        "brgen/app/assets/stylesheets/application.scss (posts, nav, forms)" =>
          sample_css("brgen", Regexp.union(SAMPLES.values_at(:posts, :nav, :forms))),
        "shared/app/assets/stylesheets/_minimal.scss" => read_css(File.join(RAILS, "shared/app/assets/stylesheets/_minimal.scss")),
      }
      samples.each do |rel, css|
        DesignMetrics.extract_line_heights(css).each do |lh|
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

      samples = {
        "brgen/app/assets/stylesheets/application.scss (marketplace)" => sample_css("brgen", SAMPLES[:marketplace]),
        "shared/app/assets/stylesheets/_minimal.scss" => read_css(File.join(RAILS, "shared/app/assets/stylesheets/_minimal.scss")),
      }
      off = []
      samples.each do |rel, css|
        DesignMetrics.extract_spacing_px(css).each do |px|
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

      inventory = Inventory.new(root: ROOT).apps.find { |a| a.name == "brgen" }
      unless inventory && CrawlSupport.port_open?("127.0.0.1", inventory.port)
        @result.skipped_live("design_metrics browser: brgen port closed — skip live hit targets")
        return
      end

      min_px = @rules.dig("layout_rules", "touch", "target_min_px").to_i
      probes = [
        { label: "core", path: "/", selector: ".tab-item, .compose-btn, a.tab-item" },
        { label: "marketplace", path: "/", selector: "#navBar a, .deal-fav, .btn" },
        { label: "nearby", path: "/nearby", selector: ".btn, .nearby-locate-actions button" },
      ]
      surfaces = probes.filter_map do |probe|
        GeometryProbe.surfaces(root: ROOT).find do |surface|
          surface.app == "brgen" && surface.label == probe[:label] && surface.path == probe[:path] && surface.viewport == "mobile"
        end.then { |surface| surface && [surface, probe] }
      end
      if surfaces.empty?
        @result.skipped_live("design_metrics browser: no matching brgen GeometryProbe surfaces")
        return
      end

      GeometryProbe.with_browser(root: ROOT, warm: surfaces.map(&:first)) do |cdp|
        surfaces.each do |surface, probe|
          @result.checked!
          cdp.viewport(surface.width, surface.height, mobile: surface.width < 500)
          cdp.headers(GeometryProbe::PROBE_HEADERS)
          cdp.clear_cookies
          cdp.navigate(surface.url)
          rows = cdp.evaluate(
            "Array.from(document.querySelectorAll(#{probe[:selector].to_json})).slice(0,5).map(el => { const r = el.getBoundingClientRect(); return { width: r.width, height: r.height }; })"
          )
          unless rows.is_a?(Array) && rows.any?
            @result.fail("design_metrics browser: no elements for #{probe[:selector]} on #{probe[:path]}", severity: :soft)
            next
          end
          rows.each do |row|
            next unless row.is_a?(Hash)
            h = row["height"].to_f
            w = row["width"].to_f
            next if h < 1 || w < 1
            next unless [h, w].min + 0.5 < min_px

            @result.fail(
              "design_metrics browser: #{probe[:path]} element ~#{w.to_i}×#{h.to_i} < #{min_px}px (principle=fitts_law)",
              severity: :hard
            )
          end
        end
      end
    rescue StandardError => e
      @result.inconclusive!("design_metrics browser: #{e.class}: #{e.message}")
    end
    def read_css(path)
      raise "design_metrics: required stylesheet missing: #{path}" unless File.file?(path)

      File.read(path)
    rescue StandardError => e
      raise "design_metrics: required stylesheet unreadable: #{path}: #{e.class}: #{e.message}"
    end
  end
end
