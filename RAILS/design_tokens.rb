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

  def face_root_css
    data = load.fetch("face_root")
    anchors = data.fetch("anchors")
    derived = data.fetch("derived")
    layout = data.fetch("layout")
    lines = [":root {"]
    FACE_ORDER.each do |key|
      lines << "  --#{key.tr('_', '-')}: #{anchors.fetch(key)};"
    end
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
    data = load
    face_anchors = data.fetch("face_root").fetch("anchors")
    social = data.fetch("social")
    drifted = []

    face_anchors.each do |key, value|
      next if key == "x_text"

      needle = "$#{key.tr('_', '-')}: #{value}"
      drifted << "#{key}=#{value}" unless scss.include?(needle)
    end

    social_text = social.fetch("x_text")
    drifted << "x_text=#{social_text}" unless scss.include?("$text: #{social_text}")

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
