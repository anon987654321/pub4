# frozen_string_literal: true

module Master
  module Design
    class MobileFirstPwaProfiles
      Rule = Data.define(:id, :pattern, :extract, :threshold, :message, :severity)

      TOUCH_TARGET_MIN_PX = Master::Ground::Axioms::Wcag::TOUCH_TARGET_AAA_PX
      BODY_FONT_MIN_PX = Master::Ground::Axioms::Wcag::BODY_FONT_MIN_PX
      LINE_HEIGHT_MIN = Master::Ground::Axioms::Wcag::LINE_HEIGHT_MIN
      LINE_LENGTH_MIN_CH = 45
      LINE_LENGTH_MAX_CH = 75

      CSS_RULES = [
        Rule.new(
          id: :font_size_too_small,
          pattern: /(?:^|[{\s;])font-size:\s*(\d+)px/,
          extract: ->(m) { m[0].to_i },
          threshold: BODY_FONT_MIN_PX,
          message: "font-size %dpx below #{BODY_FONT_MIN_PX}px baseline",
          severity: :high,
        ),
        Rule.new(
          id: :line_height_too_low,
          pattern: /line-height:\s*([\d.]+)(?!px|em|rem)/,
          extract: ->(m) { m[0].to_f },
          threshold: LINE_HEIGHT_MIN,
          message: "line-height %.1f below #{LINE_HEIGHT_MIN} — readability baseline",
          severity: :medium,
        ),
        Rule.new(
          id: :touch_target_too_small,
          pattern: /min-height:\s*(\d+)px/,
          extract: ->(m) { m[0].to_i },
          threshold: TOUCH_TARGET_MIN_PX,
          message: "min-height %dpx below #{TOUCH_TARGET_MIN_PX}px WCAG touch target (2.5.8)",
          severity: :high,
        ),
      ].freeze

      PATTERN_RULES = [
        Rule.new(
          id: :animation_no_reduced_motion,
          pattern: /(?:animation|transition)\s*:/,
          extract: nil,
          threshold: nil,
          message: "animation/transition without @media (prefers-reduced-motion: reduce) guard",
          severity: :medium,
        ),
        Rule.new(
          id: :raw_primary_color,
          pattern: /#(?:ff0000|00ff00|0000ff|ffff00|ff00ff|00ffff)\b/i,
          extract: nil,
          threshold: nil,
          message: "raw primary color — use shadow/midtone/highlight graded triplets",
          severity: :low,
        ),
        Rule.new(
          id: :linear_timing,
          pattern: /transition:[^;]*\blinear\b/,
          extract: nil,
          threshold: nil,
          message: "linear timing function — prefer ease-out or cubic-bezier for perceived smoothness",
          severity: :low,
        ),
      ].freeze

      HTML_CHECKS = {
        landmarks: { pattern: /<main|<nav\b|<header\b|<footer\b/,
          message: "no landmark elements — add <main>, <nav>, <header>, <footer>", severity: :high },
        form_labels: { pattern: /<label\b/,
          message: "form found but no <label> elements", severity: :medium },
      }.freeze

      def audit(app_path)
        css_findings = audit_css(app_path)
        html_findings = audit_html(app_path)
        all = css_findings + html_findings
        { violations: all, severity_counts: all.group_by { |v| v[:severity] }.transform_values(&:count) }
      end

      def recommendations(audit_result)
        Array(audit_result[:violations])
          .sort_by { |v| %i[high medium low].index(v[:severity]) || 9 }
          .map { |v| heuristic_prefix(v) + "[#{v[:severity].upcase}] #{v[:id]}: #{v[:message]}" }
      end

      private

      HEURISTIC_MAP = {
        font_size_too_small: :h8_minimalism,
        line_height_too_low: :h8_minimalism,
        touch_target_too_small: :h6_recognition,
        animation_no_reduced_motion: :h8_minimalism,
        raw_primary_color: :h8_minimalism,
        linear_timing: :h8_minimalism,
        landmarks: :h4_consistency,
        focus_ring: :h6_recognition,
        form_labels: :h5_error_prevention,
      }.freeze

      def heuristic_prefix(violation)
        key = violation.is_a?(Hash) ? violation[:id]&.to_sym : nil
        h_key = HEURISTIC_MAP[key]
        return "" unless h_key
        "[Nielsen ##{Master::Ground::Axioms::UxHeuristics.number(h_key)}] "
      end

      def audit_css(path)
        css_files = Dir.glob(File.join(path, "**", "*.{css,scss}"))
          .reject { |f| f.include?("node_modules") || f.include?("vendor") || f.include?("/builds/") || f.include?("/public/assets/") }
        findings = []
        css_files.each { |file| audit_css_file(file, findings) }
        findings << focus_ring_finding(css_files) unless any_focus_ring_style?(css_files)
        findings
      end

      def any_focus_ring_style?(css_files)
        css_files.any? { |f| readable_css(f).match?(/focus-visible|:focus\b/) }
      end

      def readable_css(file)
        File.read(file)
      rescue StandardError
        ""
      end

      def focus_ring_finding(css_files)
        { id: :focus_ring, file: css_files.empty? ? "(no stylesheets)" : "(stylesheets)",
          message: "no focus-visible styles found", severity: :high }
      end

      def audit_css_file(file, findings)
        source = File.read(file)
        collect_css_rule_findings(source, file, findings)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "MobileFirstPwaProfiles.audit_css_file", path: file)
        nil
      end

      def collect_css_rule_findings(source, file, findings)
        has_reduced_motion = source.match?(/prefers-reduced-motion/)

        CSS_RULES.each do |rule|
          source.scan(rule.pattern) do |m|
            value = rule.extract&.call(m)
            # line-height: 0 collapses inline-box whitespace under wrapped SVG/img logos — not body text.
            next if rule.id == :line_height_too_low && value && value < 1.0
            next if value && value >= rule.threshold
            finding_message = value ? format(rule.message, value) : rule.message
            findings << { id: rule.id, file:, message: finding_message, severity: rule.severity }
          end
        end

        PATTERN_RULES.each do |rule|
          next unless source.match?(rule.pattern)
          next if rule.id == :animation_no_reduced_motion && has_reduced_motion
          findings << { id: rule.id, file:, message: rule.message, severity: rule.severity }
        end
      end

      def audit_html(path)
        erb_files = Dir.glob(File.join(path, "**", "*.html.{erb,haml}"))
          .reject { |f| f.include?("vendor") }
        if erb_files.empty?
          return [{ id: :no_html, file: path, message: "no HTML/ERB files found", severity: :medium }]
        end

        combined = erb_files.first(40).map { |f| File.read(f) rescue "" }.join("\n")
        findings = []

        HTML_CHECKS.each do |check_id, spec|
          has_form = combined.match?(/<form\b/)
          next if check_id == :form_labels && !has_form
          next if combined.match?(spec[:pattern])
          findings << { id: check_id, file: "(views)", message: spec[:message], severity: spec[:severity] }
        end

        findings
      end
    end

    module PlatformProfiles
      PROFILES = {
        brutal_minimal: {
          philosophy: "content-first, invisible design, delete anything that does not improve readability",
          layout: %w[single_column semantic_html system_fonts black_white max_65ch],
          avoid: %w[shadows glows gradients rounded_corners decorative_borders
            hero_banners loading_theatrics custom_fonts],
          metrics: { max_total_kb: 10, contrast: 4.5, line_min_ch: 45, line_max_ch: 75 },
        },
        medium: {
          philosophy: "long-form reading comfort through generous side whitespace and typographic rhythm",
          layout: %w[article_column max_65ch large_line_height restrained_navigation],
          avoid: %w[visual_noise dense_sidebars auto_play],
          metrics: { line_height: 1.58, max_width_px: 680 },
        },
        substack: {
          philosophy: "newsletter-first trust, direct author voice, low-friction subscription",
          layout: %w[publication_header readable_feed email_capture simple_article],
          avoid: %w[overdesigned_cards hidden_authors distracting_motion],
          metrics: { cta_count: 1, line_max_ch: 75 },
        },
        new_yorker: {
          philosophy: "editorial authority, strong type hierarchy, content as cultural object",
          layout: %w[serif_editorial strong_headlines generous_margins disciplined_grid],
          avoid: %w[cheap_gradients excessive_chrome noisy_cards],
          metrics: { contrast: 4.5, font_families_max: 2 },
        },
        x: {
          philosophy: "dense real-time feed optimized for scanning and interaction velocity",
          layout: %w[feed timeline compact_actions sticky_navigation],
          avoid: %w[slow_animation large_cards_hidden_content],
          metrics: { action_target_px: 44 },
        },
        tiktok: {
          philosophy: "full-screen media-first flow with minimal chrome and immediate feedback",
          layout: %w[full_screen_media vertical_flow gesture_first],
          avoid: %w[text_heavy_chrome slow_load blocking_modals],
          metrics: { first_frame_ms: 500 },
        },
      }.freeze

      module_function

      def fetch(name)
        PROFILES.fetch(name.to_sym)
      end

      def brief(name)
        profile = fetch(name)
        parts = ["#{name}: #{profile[:philosophy]}", "layout=#{profile[:layout].join(', ')}",
          "avoid=#{profile[:avoid].join(', ')}", "metrics=#{profile[:metrics]}"]
        parts.join("; ")
      end

      def constraints(name)
        profile = fetch(name)
        [
          "philosophy: #{profile[:philosophy]}",
          "layout: #{profile[:layout].join(', ')}",
          "avoid: #{profile[:avoid].join(', ')}",
          "metrics: #{profile[:metrics]}",
        ]
      end

      def choose(text)
        source = text.to_s.downcase
        return :brutal_minimal if source.match?(/brutal|minimal|motherfucking|content-first|black.?white/)
        return :substack if source.include?("substack") || source.include?("newsletter")
        return :tiktok if source.include?("tiktok") || source.include?("short video")

        :brutal_minimal
      end
    end

    # The design-tier rules of data/rules.yml, for scanners and UI critique.
    class Thresholds
      def self.load(root: Master::ROOT)
        Master.design_rules(root:)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Design::Thresholds.load")
        {}
      end

      def self.dig(*keys, root: Master::ROOT)
        load(root:).dig(*keys)
      end

      # `dig` is private because every key worth reading has a named accessor
      # below, and a bare dig from outside is how a second spelling of the same
      # threshold gets introduced.
      #
      # `load` is public because the section is also read wholesale: the voice
      # personality builds one prompt line per design concern and wants the
      # whole hash, not eight separate calls. Making it private satisfies an
      # abstraction count and breaks that caller, and a private method with two
      # callers outside the class is not an abstraction — it is an outage.
      private_class_method :dig

      def self.touch_min_px(root: Master::ROOT)
        # layout_rules.touch and ux_laws.fitts are one YAML value (&touch_min_px).
        dig("layout_rules", "touch", "target_min_px", root:) || 44
      end

      def self.max_visible_choices(root: Master::ROOT)
        dig("ux_laws", "hick", "max_visible_choices", root:) || 7
      end

      def self.worn_type(root: Master::ROOT)
        dig("worn_type", root:) || {}
      end

      def self.worn_profile(name, root: Master::ROOT)
        profiles = worn_type(root:)["profiles"] || {}
        feed = profiles["feed"] || {}
        spec = profiles[name.to_s] || {}
        feed.merge(spec).merge("name" => name.to_s)
      end

      def self.allowed_line_heights(root: Master::ROOT)
        raw = dig("typography", "line_height", "allowed", root:)
        return raw.map(&:to_f) if raw.is_a?(Array) && !raw.empty?

        # Same steps as RAILS/shared/design_tokens.yml scale.line_height / ScaleLint
        [1.0, 1.25, 1.4, 1.5, 1.6]
      end

      def self.body_line_height_preferred(root: Master::ROOT)
        dig("typography", "line_height", "body_preferred", root:) || 1.5
      end

      def self.measure_ideal_ch(root: Master::ROOT)
        dig("typography", "optical_margins", "measure_ideal_ch", root:) ||
          dig("typography", "line_length", "ideal_ch", root:) || 66
      end

      def self.micro_typography(root: Master::ROOT)
        dig("typography", "micro", root:) || {}
      end

      def self.eight_px_rhythm(root: Master::ROOT)
        # pixel_perfection.eight_px_rhythm aliases layout_rules.grid.allowed_spacing_px.
        dig("pixel_perfection", "eight_px_rhythm", root:) ||
          [0, 4, 8, 12, 16, 20, 24, 32, 40, 44, 48, 64, 96]
      end
    end
  end
end
