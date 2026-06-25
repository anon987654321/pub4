# frozen_string_literal: true

require "active_support/core_ext/object/blank"
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
    COLOR_INHERIT_PATTERN = /color:\s*inherit\b/
    EXCLUDED_PATH_PATTERN = %r{
      (?:^|/)(?:vendor|node_modules|tmp|log|storage|coverage)(?:/|$)
      |(?:^|/)app/assets/builds/
      |lightgallery\.css
      |actiontext\.css
      |frontend/layouts/visualizer
      |minimal-ui\.css
    }ix
    MAILER_STYLE_PATH_PATTERN = %r{(?:layouts/(?:mailer|_mailer_styles)|_mailer/)}
    MAILER_VIEW_PATH_PATTERN = %r{views/[^/]*_mailer/}i
    ALLOWED_IMPORTANT_PATTERN = /@media\s*\(\s*prefers-reduced-motion|@media\s+print/i

    def self.call(root:, changed_paths: nil)
      new(root: root, changed_paths: changed_paths).call
    end

    def initialize(root:, changed_paths: nil)
      @root = Pathname(root)
      @changed_paths = Array(changed_paths).presence
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
      add(:error, path, :embedded_app_file, "Shell script appears to write tracked app files; extract embedded content") if body.match?(SHELL_EMBED_PATTERN)
      add(:warning, path, :mixed_shebang, "Shell script has both bash and zsh shebangs") if body.include?("#!/bin/bash") && body.include?("#!/usr/bin/env zsh")
    end

    def scan_view(path, body)
      mailer_view = path.match?(MAILER_STYLE_PATH_PATTERN) || path.match?(MAILER_VIEW_PATH_PATTERN)
      unless mailer_view
        add(:warning, path, :inline_css, "Inline <style> block found; extract to tracked stylesheet") if body.match?(INLINE_STYLE_PATTERN)
      end
      if body.match?(INLINE_STYLE_ATTR_PATTERN) && !css_var_only_styles?(body) && !mailer_view
        add(:warning, path, :inline_style_attr, "Inline style= attribute found; move to application.scss")
      end
      add(:warning, path, :inline_javascript, "Inline <script> block found; extract to tracked JavaScript") if body.match?(INLINE_SCRIPT_PATTERN)
      add(:info, path, :chartjs, "Chart.js detected; protect config/data separation") if body.match?(CHART_PATTERN)
    end

    def scan_style(path, body)
      add(:info, path, :keyframes, "Keyframes detected; mark restored animations as protected") if body.match?(KEYFRAMES_PATTERN)
      add(:info, path, :font_face, "Font-face detected; keep font declarations in dedicated/protected file") if body.match?(FONT_FACE_PATTERN)
      add(:warning, path, :important, "Use of !important detected; prefer cascade and specificity") if important_violations?(body)
      add(:warning, path, :logical_properties, "Physical left/right properties detected; prefer logical properties") if body.match?(LOGICAL_PROPERTY_PATTERN)
      if body.lines.size > Shared::FrontendRuleSet::TYPOGRAPHY[:max_css_file_lines] && !css_file_size_exempt?(path, body)
        add(:warning, path, :css_file_size, "CSS file exceeds #{Shared::FrontendRuleSet::TYPOGRAPHY[:max_css_file_lines]} lines; split into smaller files")
      end
      add(:warning, path, :selector_specificity, "Selector exceeds #{Shared::FrontendRuleSet::TYPOGRAPHY[:max_selector_classes]} class selectors; flatten the selector chain") if selector_depths(body).any? { |depth| depth > Shared::FrontendRuleSet::TYPOGRAPHY[:max_selector_classes] }
      add(:warning, path, :will_change, "will-change detected; restrict it to active animations or component connect/disconnect hooks") if body.match?(WILL_CHANGE_PATTERN)
      add(:warning, path, :paint_cost, "box-shadow hover detected; prefer background-color, opacity, or transform for hover states") if body.match?(BOX_SHADOW_HOVER_PATTERN)
      add(:info, path, :color_inherit, "color: inherit detected; good for preventing default link colors") if body.match?(COLOR_INHERIT_PATTERN)
      body.scan(/font-size:\s*(\d+(?:\.\d+)?)px/i).flatten.each do |size|
        add(:warning, path, :small_font, "Font size #{size}px is below 16px") if size.to_f < Shared::FrontendRuleSet::TYPOGRAPHY[:body_font_px][:min]
      end
    end

    def scan_javascript(path, body)
      add(:info, path, :chartjs, "Chart.js config detected; separate chart data from options") if body.match?(CHART_PATTERN)
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
      findings << Finding.new(severity: severity, path: path, rule: rule, message: message)
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

    def css_file_size_exempt?(path, body)
      return true if path.end_with?("application.scss") && body.lines.all? { |line| line.strip.empty? || line.strip.start_with?("@use", "@forward", "@import") }
      return true if path.end_with?("application.scss") && body.lines.size <= 400
      return true if path.match?(/_(?:minimal|zen_shell|tokens|animations|pub4_stack)\.scss\z/)
      return true if path.match?(/(?:minimal-ui(?:-\d+)?|_zen_shell|_tokens|_animations|_pub4_stack)\.(?:css|scss)\z/)

      false
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