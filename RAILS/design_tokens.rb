#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

module DesignTokens
  ROOT = File.expand_path(__dir__)
  SOURCE = File.join(ROOT, "shared", "design_tokens.yml")
  FACE_ORDER = %w[c_text x_text c_accent c_danger c_code].freeze

  module_function

  def read_utf8(path)
    File.read(path, encoding: "UTF-8")
  end

  def load
    YAML.safe_load_file(SOURCE) || {}
  end

  def social_token_lines
    social = load.fetch("social")
    social.map { |key, value| "  --#{key.tr('_', '-')}: #{value};" }
  end

  def face_root_css
    data = load.fetch("face_root")
    anchors = data.fetch("anchors")
    derived = data.fetch("derived")
    layout = data.fetch("layout")
    lines = [":root {"]
    FACE_ORDER.each do |key|
      lines << "  --#{key.tr('_', '-')}: #{anchors.fetch(key)};"
    end
    lines.concat(social_token_lines)
    lines << "  --x-weight-normal: 400;"
    lines << "  --x-weight-medium: 500;"
    lines << "  --x-weight-bold: 700;"
    lines << "  --x-weight-heavy: 800;"
    lines << "  --x-radius-xs: 4px;"
    lines << "  --x-radius-sm: 8px;"
    lines << "  --x-radius-md: 12px;"
    lines << "  --x-radius-pill: 9999px;"
    lines << "  --x-radius-card: 16px;"
    lines << "  --x-radius-lg: 16px;"
    lines << "  --bg: var(--x-bg);"
    lines << "  --surface: var(--x-surface);"
    lines << "  --surface2: var(--x-surface-elevated);"
    lines << "  --search-bg: var(--x-search-bg);"
    lines << "  --text: var(--x-text);"
    lines << "  --text-dim: var(--x-text-secondary);"
    lines << "  --accent: var(--x-accent);"
    lines << "  --accent-hover: var(--x-accent-hover);"
    lines << "  --border: var(--x-border);"
    lines << "  --hover: var(--x-hover);"
    lines << "  --hover-subtle: var(--x-hover-subtle);"
    lines << "  --radius: var(--x-radius-card);"
    lines << "  --radius-pill: var(--x-radius-pill);"
    lines << "  --sp: 8px;"
    lines << "  --sidebar-width: var(--x-sidebar);"
    lines << "  --widgets-width: var(--x-widgets);"
    lines << "  --feed-max: var(--x-feed-max);"
    lines << "  --x-font-mono: #{data.fetch('font_mono')};"
    lines << "  --font-label: #{data.fetch('font_label')};"
    lines << "  color-scheme: dark;"
    %w[top right bottom left].each do |side|
      lines << "  --safe-#{side}: env(safe-area-inset-#{side}, 0px);"
    end
    { "t" => "top", "r" => "right", "b" => "bottom", "l" => "left" }.each do |short, side|
      lines << "  --inset-#{short}: calc(12px + var(--safe-#{side}));"
    end
    lines << "  --face-bg: #{data.fetch('face_bg')};"
    derived.each { |k, v| lines << "  --#{k.tr('_', '-')}: #{v};" }
    layout.each do |k, v|
      lines << "  /* canvas-only knobs: read via getComputedStyle in face.runtime.js, not consumed by any CSS rule below */" if k == "face-particle-size"
      lines << "  /* z-scale: canvas(base) < chrome(persistent HUD) < ui < overlay(panels) < modal(blocking) < toast(errors) < skip(a11y skip-link) */" if k == "z-canvas"
      lines << "  --#{k}: #{v};"
    end
    lines << "}"
    lines.join("\n")
  end

  def face_root_block
    <<~CSS.strip
      /* BEGIN:generated-face-root — ruby RAILS/scripts/generate_face_root_css.rb */
      #{face_root_css}
      /* END:generated-face-root */
    CSS
  end

  def sync_face_css!(path)
    body = read_utf8(path)
    pattern = %r{/\* BEGIN:generated-face-root.*?\*/.*?/\* END:generated-face-root \*/}m
    unless body.match?(pattern)
      abort "design_tokens: missing generated-face-root markers in #{path}"
    end
    updated = body.sub(pattern, face_root_block)
    return false if updated == body

    File.write(path, updated)
    true
  end

  def scss_anchor_drift?(path = File.join(ROOT, "shared", "app", "assets", "stylesheets", "_x_base.scss"))
    return "missing #{path}" unless File.file?(path)

    scss = read_utf8(path)
    anchors = load.fetch("face_root").fetch("anchors")
    drifted = anchors.filter_map do |key, value|
      needle = key == "x_text" ? "$text: #{value}" : "$#{key.tr('_', '-')}: #{value}"
      "#{key}=#{value}" unless scss.include?(needle)
    end
    return nil if drifted.empty?

    "_x_base.scss defaults drifted from design_tokens.yml anchors: #{drifted.join(', ')}"
  end

  def face_root_drift?(path)
    body = read_utf8(path)
    pattern = %r{/\* BEGIN:generated-face-root.*?\*/(.*?)/\* END:generated-face-root \*/}m
    match = body.match(pattern)
    return "missing generated-face-root markers" unless match

    actual = match[1].strip
    expected = face_root_css
    return nil if actual == expected

    "face.css :root drift — run: ruby RAILS/scripts/generate_face_root_css.rb"
  end
end