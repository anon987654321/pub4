# frozen_string_literal: true

require_relative "frontend_rule_set"

module Shared
  class FrontendAuditor
    Finding = Struct.new(:severity, :path, :rule, :message, keyword_init: true)

    INLINE_STYLE_PATTERN = /<style[\s>]/i
    INLINE_STYLE_ATTR_PATTERN = /\sstyle\s*=\s*["']/
    INLINE_SCRIPT_PATTERN = /<script(?![^>]+src=)[\s>]/i
    SHELL_EMBED_PATTERN = /cat\s+<<[-~]?\s*['\"]?\w+['\"]?\s*>\s*(app|config|db|public)\//
    KEYFRAMES_PATTERN = /@keyframes\s+[a-zA-Z0-9_-]+/
    FONT_FACE_PATTERN = /@font-face/
    CHART_PATTERN = /new\s+Chart\s*\(|Chart\.getChart|chart\.js/i
    IMPORTANT_PATTERN = /!important\b/
    LOGICAL_PROPERTY_PATTERN = /^\s*(margin|padding|inset)-(left|right)\s*:|^\s*left\s*:|^\s*right\s*:/
    CLASS_SELECTOR_PATTERN = /(^|[\s,{>+~])\.([a-zA-Z0-9_-]+)/
    WILL_CHANGE_PATTERN = /will-change\s*:/
    BOX_SHADOW_HOVER_PATTERN = /:hover[^{]*\{[^}]*box-shadow\s*:|box-shadow\s*:[^;]+;[^}]*:hover/i
    BOX_SHADOW_PATTERN = /box-shadow\s*:\s*(?!none\b)/i
    BACKDROP_BLUR_PATTERN = /backdrop-filter\s*:\s*blur\(|filter\s*:[^;]*\bblur\(/i
    COLOR_INHERIT_PATTERN = /color:\s*inherit\b/
    BEM_IN_VIEW_PATTERN = /class=["'][^"']*__[^"']*["']/
    UTILITY_SOUP_PATTERN = /class=["'][^"']*(?:\b(?:mt|mb|ml|mr|px|py|col|row|d-flex)\b[^"']*){3,}/i
    DIV_NESTING_PATTERN = /<div[^>]*>\s*<div[^>]*>\s*<div[^>]*>\s*<div/i
    INVALID_PARAGRAPH_BLOCK_PATTERN = /<p\b[^>]*>\s*<(?:div|section|article|form|nav|ul|ol)\b/i
    EMPTY_LANDMARK_PATTERN = /<(nav|main|aside|section)\b[^>]*>\s*<\/\1>/im
    LONG_TRANSITION_PATTERN = /transition(?:-duration)?\s*:\s*([4-9]\d\d|\d{4,})\s*ms/i
    CENTERED_PROSE_PATTERN = /text-align:\s*center/i
    MAX_CONTENT_WIDTH_PATTERN = /max-width:\s*(\d+(?:\.\d+)?)(ch|rem)/
    # Product pens (yep search, jOxVvNE, Amazon nav) keep exact CSS including shadows.
    PEN_STYLE_PATH_PATTERN = %r{
      (?:^|/)(?:_search_yep|_jsfiddle_chrome|_marketplace_nav_bar|_marketplace_animated_logo)\.scss\z
    }ix
    EXCLUDED_PATH_PATTERN = %r{
      (?:^|/)(?:vendor|node_modules|tmp|log|storage|coverage)(?:/|$)
      |(?:^|/)app/assets/builds/
      |lightgallery\.css
      |swiper-bundle(?:\.min)?\.css
      |public/dilla/
      |actiontext\.css
      |public/assets/.*-[a-f0-9]{6,}\.(?:css|scss|js|erb|html)\z
      |minimal-ui\.css
    }ix
    MAILER_STYLE_PATH_PATTERN = %r{(?:layouts/(?:mailer|_mailer_styles)|_mailer/)}
    MAILER_VIEW_PATH_PATTERN = %r{views/[^/]*_mailer/}i
    ALLOWED_IMPORTANT_PATTERN = /@media\s*\(\s*prefers-reduced-motion|@media\s+print/i

    def self.call(root:, changed_paths: nil)
      new(root:, changed_paths:).call
    end

    def initialize(root:, changed_paths: nil)
      @root = Pathname(root)
      paths = Array(changed_paths).reject { |path| path.to_s.empty? }
      @changed_paths = paths.empty? ? nil : paths
      @findings = []
    end

    def call
      scan_files.each { |path| scan(path) }
      findings
    end

    private

    attr_reader :root, :changed_paths, :findings

    def scan_files
      paths = if changed_paths
        changed_paths.map { |path| root.join(path) }
      else
        root.glob("**/*")
      end
      paths.select(&:file?).reject { |path| excluded_path?(path.relative_path_from(root).to_s) }
    end

    def scan(path)
      relative = path.relative_path_from(root).to_s
      return if excluded_path?(relative)

      body = path.read

      scan_shell(relative, body) if relative.end_with?(".sh")
      scan_view(relative, body) if relative.match?(/\.(erb|html)$/)
      scan_style(relative, body) if relative.match?(/\.(css|scss|sass)$/)
      scan_javascript(relative, body) if relative.match?(/\.(js|mjs|ts)$/)
    rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
      add(:warning, relative, :encoding, "Could not scan file due encoding issue")
    end

    def scan_shell(path, body)
      add(:error, path, :embedded_app_file,
"Shell script appears to write tracked app files; extract embedded content") if body.match?(SHELL_EMBED_PATTERN)
      add(:warning, path, :mixed_shebang,
"Shell script has both bash and zsh shebangs") if body.include?("#!/bin/bash") && body.include?("#!/usr/bin/env zsh")
    end

    def scan_view(path, body)
      mailer_view = path.match?(MAILER_STYLE_PATH_PATTERN) || path.match?(MAILER_VIEW_PATH_PATTERN)
      unless mailer_view
        add(:warning, path, :inline_css,
"Inline <style> block found; extract to tracked stylesheet") if body.match?(INLINE_STYLE_PATTERN)
      end
      if body.match?(INLINE_STYLE_ATTR_PATTERN) && !css_var_only_styles?(body) && !mailer_view
        add(:warning, path, :inline_style_attr, "Inline style= attribute found; move to application.scss")
      end
      add(:warning, path, :inline_javascript,
"Inline <script> block found; extract to tracked JavaScript") if body.match?(INLINE_SCRIPT_PATTERN)
      add(:info, path, :chartjs, "Chart.js detected; protect config/data separation") if body.match?(CHART_PATTERN)
      add(:warning, path, :bem_in_views,
"BEM class in view — use bare tag targeting") if body.match?(BEM_IN_VIEW_PATTERN)
      add(:warning, path, :utility_class_soup,
"Utility class soup in view — move to SCSS") if body.match?(UTILITY_SOUP_PATTERN)
      add(:warning, path, :anti_divitis,
"Deep div nesting — flatten or use semantic landmarks") if body.match?(DIV_NESTING_PATTERN)
      add(:warning, path, :invalid_paragraph_block,
"Block element nested directly inside <p>; use a field or semantic wrapper") if body.match?(INVALID_PARAGRAPH_BLOCK_PATTERN)
      add(:warning, path, :empty_landmark,
"Empty landmark found; remove it until it contains meaningful content") if body.match?(EMPTY_LANDMARK_PATTERN)
      if path.match?(%r{(?:\A|/)app/views/}) && !layout_path?(path) && body.match?(/<main\b/i)
        add(:warning, path, :nested_main, "View defines <main> inside the application layout; use section or div")
      end
      if body.scan(/turbo-cache-control/i).size > 1
        add(:warning, path, :duplicate_turbo_cache_control, "Multiple Turbo cache-control directives found")
      end
      add(:warning, path, :skip_to_main, "Layout missing skip link to #main-content") if layout_missing_skip?(path,
body)
      add(:warning, path, :single_h1, "Multiple h1 tags in one view") if body.scan(/<h1\b/i).size > 1
    end

    def scan_style(path, body)
      # Documented product pens (yep search, jOx, Amazon nav/logo) keep exact CSS —
      # same allow-list as css_constitution / GateAutofix. Do not hygiene-fail them.
      if path.match?(PEN_STYLE_PATH_PATTERN)
        add(:info, path, :product_pen, "Documented product pen — exact CSS preserved (constitution allow-list)")
        return
      end

      add(:info, path, :keyframes,
"Keyframes detected; mark restored animations as protected") if body.match?(KEYFRAMES_PATTERN)
      add(:info, path, :font_face,
"Font-face detected; keep font declarations in dedicated/protected file") if body.match?(FONT_FACE_PATTERN)
      add(:warning, path, :important,
"Use of !important detected; prefer cascade and specificity") if important_violations?(body)
      add(:warning, path, :logical_properties,
"Physical left/right properties detected; prefer logical properties") if body.match?(LOGICAL_PROPERTY_PATTERN)
      if css_file_size_violation?(path, body)
        add(:warning, path, :css_file_size,
"CSS file exceeds #{Shared::FrontendRuleSet::TYPOGRAPHY[:max_css_file_lines]} lines; split into smaller files")
      end
      add(:warning, path, :selector_specificity,
"Selector exceeds #{Shared::FrontendRuleSet::TYPOGRAPHY[:max_selector_classes]} class selectors; flatten the selector chain") if selector_depths(body).any? { |depth|
 depth > Shared::FrontendRuleSet::TYPOGRAPHY[:max_selector_classes] }
      add(:warning, path, :will_change,
"will-change detected; restrict it to active animations or component connect/disconnect hooks") if body.match?(WILL_CHANGE_PATTERN)
      add(:warning, path, :paint_cost,
"box-shadow hover detected; prefer background-color, opacity, or transform for hover states") if body.match?(BOX_SHADOW_HOVER_PATTERN)
      add(:warning, path, :flat_design,
"box-shadow detected; this repo's design system is flat -- use a 1px border for separation instead") if body.match?(BOX_SHADOW_PATTERN)
      add(:warning, path, :flat_design,
"backdrop-filter/filter blur() detected; this repo's design system is flat -- use a solid background instead") if body.match?(BACKDROP_BLUR_PATTERN)
      add(:info, path, :color_inherit,
"color: inherit detected; good for preventing default link colors") if body.match?(COLOR_INHERIT_PATTERN)
      scan_style_measurements(path, body)
    end

    # The checks that read a number out of the stylesheet and compare it to a
    # budget, split from the plain pattern matches above only because the two
    # together were over the method length ceiling.
    def scan_style_measurements(path, body)
      body.scan(/font-size:\s*(\d+(?:\.\d+)?)px/i).flatten.each do |size|
        add(:warning, path, :small_font, "Font size #{size}px is below 16px") if size.to_f < Shared::FrontendRuleSet::TYPOGRAPHY[:body_font_px][:min]
      end
      body.scan(LONG_TRANSITION_PATTERN).flatten.compact.each do |duration|
        add(:warning, path, :no_long_transition, "Transition #{duration}ms exceeds 300ms budget") if duration.to_i > Shared::FrontendRuleSet::MOTION[:max_transition_ms]
      end
      if body.match?(/@keyframes|animation\s*:/i) && !body.match?(/prefers-reduced-motion:\s*reduce/i)
        add(:info, path, :reduced_motion, "Animation without prefers-reduced-motion override")
      end
      body.scan(MAX_CONTENT_WIDTH_PATTERN).each do |value, unit|
        width = value.to_f
        next unless unit == "ch"

        range = Shared::FrontendRuleSet::TYPOGRAPHY[:line_length]
        add(:warning, path, :line_length,
"max-width #{width}ch outside #{range[:min]}-#{range[:max]}ch prose range") if width < range[:min] || width > range[:max]
      end
      add(:info, path, :centered_prose,
"Centered text block — left-align body copy per style.yml") if body.match?(CENTERED_PROSE_PATTERN)
    end

    def scan_javascript(path, body)
      add(:info, path, :chartjs,
"Chart.js config detected; separate chart data from options") if body.match?(CHART_PATTERN)
    end

    def important_violations?(body)
      return false unless body.match?(IMPORTANT_PATTERN)

      stripped = body.gsub(%r{/\*.*?\*/}m, "")
      stripped = stripped.gsub(/@media[^{]+\{(?:[^{}]|\{[^{}]*\})*\}/m) do |block|
        block.match?(ALLOWED_IMPORTANT_PATTERN) ? "" : block
      end
      stripped.match?(IMPORTANT_PATTERN)
    end

    def add(severity, path, rule, message)
      findings << Finding.new(severity:, path:, rule:, message:)
    end

    def css_var_only_styles?(body)
      styles = body.scan(/\sstyle\s*=\s*["']([^"']*)["']/i).flatten
      return false if styles.empty?

      styles.all? do |value|
        value.split(";").all? { |decl| decl.strip.empty? || decl.strip.match?(/\A--[\w-]+:\s*.+\z/) }
      end
    end

    def excluded_path?(relative)
      relative.match?(EXCLUDED_PATH_PATTERN)
    end

    def protected_stylesheet?(path)
      Shared::FrontendRuleSet::PRESERVATION[:protected_stylesheet_files].any? { |name| path.end_with?(name) }
    end

    PUB4_STACK_PARTIAL_RE = %r{/_(?:minimal|tokens|animations|zen_shell|stack|shell)(?:_brgen)?\.scss\z}

    def css_file_size_violation?(path, body)
      return false if protected_stylesheet?(path)
      return false if path.match?(PUB4_STACK_PARTIAL_RE)

      body.lines.size > Shared::FrontendRuleSet::TYPOGRAPHY[:max_css_file_lines]
    end

    def layout_missing_skip?(path, body)
      layout_path?(path) &&
        !path.match?(/(?:\A|\/)_?mailer(?:\.|_)/) &&
        !path.end_with?("/master_embed.html.erb") &&
        !body.match?(/skip|#main-content/i)
    end

    def layout_path?(path)
      path.match?(%r{(?:\A|/)app/views/layouts/})
    end

    def selector_depths(body)
      body.lines.flat_map do |line|
        next [] unless line.include?("{")
        selector = line.split("{", 2).first
        next [] if selector.include?("@media") || selector.include?("@supports") || selector.include?("@keyframes")

        selector.split(",").map { |part| part.scan(CLASS_SELECTOR_PATTERN).size }
      end
    end
  end
end
