# frozen_string_literal: true

module Master
  module Design
  class MobileFirstPwaProfiles
    Rule = Data.define(:id, :pattern, :extract, :threshold, :message, :severity)

    # WCAG 2.5.8 (AA): 24x24px minimum; 2.5.3 (AAA): 44x44px recommended
    TOUCH_TARGET_MIN_PX = 44

    # WCAG 1.4.8 / readable-typography baseline
    BODY_FONT_MIN_PX    = 16
    LINE_HEIGHT_MIN     = 1.5
    LINE_LENGTH_MIN_CH  = 45
    LINE_LENGTH_MAX_CH  = 75

    CSS_RULES = [
      Rule.new(
        id:        :font_size_too_small,
        pattern:   /(?:^|[{\s;])font-size:\s*(\d+)px/,
        extract:   ->(m) { m[1].to_i },
        threshold: BODY_FONT_MIN_PX,
        message:   "font-size %dpx below #{BODY_FONT_MIN_PX}px baseline",
        severity:  :high
      ),
      Rule.new(
        id:        :line_height_too_low,
        pattern:   /line-height:\s*([\d.]+)(?!px|em|rem)/,
        extract:   ->(m) { m[1].to_f },
        threshold: LINE_HEIGHT_MIN,
        message:   "line-height %.1f below #{LINE_HEIGHT_MIN} — readability baseline",
        severity:  :medium
      ),
      Rule.new(
        id:        :touch_target_too_small,
        pattern:   /min-height:\s*(\d+)px/,
        extract:   ->(m) { m[1].to_i },
        threshold: TOUCH_TARGET_MIN_PX,
        message:   "min-height %dpx below #{TOUCH_TARGET_MIN_PX}px WCAG touch target (2.5.8)",
        severity:  :high
      )
    ].freeze

    PATTERN_RULES = [
      Rule.new(
        id:        :animation_no_reduced_motion,
        pattern:   /(?:animation|transition)\s*:/,
        extract:   nil,
        threshold: nil,
        message:   "animation/transition without @media (prefers-reduced-motion: reduce) guard",
        severity:  :medium
      ),
      Rule.new(
        id:        :raw_primary_color,
        pattern:   /#(?:ff0000|00ff00|0000ff|ffff00|ff00ff|00ffff)\b/i,
        extract:   nil,
        threshold: nil,
        message:   "raw primary color — use shadow/midtone/highlight graded triplets",
        severity:  :low
      ),
      Rule.new(
        id:        :linear_timing,
        pattern:   /transition:[^;]*\blinear\b/,
        extract:   nil,
        threshold: nil,
        message:   "linear timing function — prefer ease-out or cubic-bezier for perceived smoothness",
        severity:  :low
      )
    ].freeze

    HTML_CHECKS = {
      landmarks:    { pattern: /<main|<nav\b|<header\b|<footer\b/, message: "no landmark elements — add <main>, <nav>, <header>, <footer>", severity: :high },
      focus_ring:   { pattern: /focus-visible|:focus\b/,            message: "no focus-visible styles found",                                severity: :high },
      form_labels:  { pattern: /<label\b/,                          message: "form found but no <label> elements",                           severity: :medium }
    }.freeze

    def audit(app_path)
      css_findings  = audit_css(app_path)
      html_findings = audit_html(app_path)
      all = css_findings + html_findings
      { violations: all, severity_counts: all.group_by { |v| v[:severity] }.transform_values(&:count) }
    end

    def recommendations(audit_result)
      Array(audit_result[:violations])
        .sort_by { |v| %i[high medium low].index(v[:severity]) || 9 }
        .map { |v| "[#{v[:severity].upcase}] #{v[:id]}: #{v[:message]}" }
    end

    private

    def audit_css(path)
      css_files = Dir.glob(File.join(path, "**", "*.{css,scss}"))
                     .reject { |f| f.include?("node_modules") || f.include?("vendor") }
      findings = []

      css_files.each do |file|
        source = File.read(file) rescue next
        has_reduced_motion = source.match?(/prefers-reduced-motion/)

        CSS_RULES.each do |rule|
          source.scan(rule.pattern) do |m|
            value = rule.extract&.call(m)
            next if value && value >= rule.threshold
            msg = value ? format(rule.message, value) : rule.message
            findings << { id: rule.id, file:, message: msg, severity: rule.severity }
          end
        end

        PATTERN_RULES.each do |rule|
          next unless source.match?(rule.pattern)
          next if rule.id == :animation_no_reduced_motion && has_reduced_motion
          findings << { id: rule.id, file:, message: rule.message, severity: rule.severity }
        end
      end

      findings
    end

    def audit_html(path)
      erb_files = Dir.glob(File.join(path, "**", "*.html.{erb,haml}"))
                     .reject { |f| f.include?("vendor") }
      return [{ id: :no_html, file: path, message: "no HTML/ERB files found", severity: :medium }] if erb_files.empty?

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
  end
end
