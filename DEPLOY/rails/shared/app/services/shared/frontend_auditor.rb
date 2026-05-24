# frozen_string_literal: true

module Shared
  class FrontendAuditor
    Finding = Struct.new(:severity, :path, :rule, :message, keyword_init: true)

    INLINE_STYLE_PATTERN = /<style[\s>]/i
    INLINE_SCRIPT_PATTERN = /<script(?![^>]+src=)[\s>]/i
    SHELL_EMBED_PATTERN = /cat\s+<<[-~]?\s*['\"]?\w+['\"]?\s*>\s*(app|config|db|public)\//
    KEYFRAMES_PATTERN = /@keyframes\s+[a-zA-Z0-9_-]+/
    FONT_FACE_PATTERN = /@font-face/
    CHART_PATTERN = /new\s+Chart\s*\(|Chart\.getChart|chart\.js/i

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
      if changed_paths
        changed_paths.map { |path| root.join(path) }.select(&:file?)
      else
        root.glob("**/*").select(&:file?)
      end
    end

    def scan(path)
      relative = path.relative_path_from(root).to_s
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
      add(:warning, path, :inline_css, "Inline <style> block found; extract to tracked stylesheet") if body.match?(INLINE_STYLE_PATTERN)
      add(:warning, path, :inline_javascript, "Inline <script> block found; extract to tracked JavaScript") if body.match?(INLINE_SCRIPT_PATTERN)
      add(:info, path, :chartjs, "Chart.js detected; protect config/data separation") if body.match?(CHART_PATTERN)
    end

    def scan_style(path, body)
      add(:info, path, :keyframes, "Keyframes detected; mark restored animations as protected") if body.match?(KEYFRAMES_PATTERN)
      add(:info, path, :font_face, "Font-face detected; keep font declarations in dedicated/protected file") if body.match?(FONT_FACE_PATTERN)
      body.scan(/font-size:\s*(\d+(?:\.\d+)?)px/i).flatten.each do |size|
        add(:warning, path, :small_font, "Font size #{size}px is below 16px") if size.to_f < Shared::FrontendRuleSet::TYPOGRAPHY[:body_font_px][:min]
      end
    end

    def scan_javascript(path, body)
      add(:info, path, :chartjs, "Chart.js config detected; separate chart data from options") if body.match?(CHART_PATTERN)
    end

    def add(severity, path, rule, message)
      findings << Finding.new(severity: severity, path: path, rule: rule, message: message)
    end
  end
end
