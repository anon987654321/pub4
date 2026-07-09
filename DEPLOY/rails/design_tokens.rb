#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

module DesignTokens
  ROOT = File.expand_path(__dir__)
  SOURCE = File.join(ROOT, "shared", "design_tokens.yml")
  FACE_ORDER = %w[c_text x_text c_accent c_danger c_code].freeze

  module_function

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
    lines << "  color-scheme: dark;"
    %w[top right bottom left].each do |side|
      lines << "  --safe-#{side}: env(safe-area-inset-#{side}, 0px);"
    end
    lines << "  --face-bg: #{data.fetch('face_bg')};"
    derived.each { |k, v| lines << "  --#{k.tr('_', '-')}: #{v};" }
    layout.each { |k, v| lines << "  --#{k}: #{v};" }
    lines << "}"
    lines.join("\n")
  end

  def face_root_block
    <<~CSS.strip
      /* BEGIN:generated-face-root — ruby DEPLOY/rails/scripts/generate_face_root_css.rb */
      #{face_root_css}
      /* END:generated-face-root */
    CSS
  end

  def sync_face_css!(path)
    body = File.read(path)
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

    scss = File.read(path)
    anchors = load.fetch("face_root").fetch("anchors")
    drifted = anchors.filter_map do |key, value|
      needle = key == "x_text" ? "$text: #{value}" : "$#{key.tr('_', '-')}: #{value}"
      "#{key}=#{value}" unless scss.include?(needle)
    end
    return nil if drifted.empty?

    "_x_base.scss defaults drifted from design_tokens.yml anchors: #{drifted.join(', ')}"
  end

  def face_root_drift?(path)
    body = File.read(path)
    pattern = %r{/\* BEGIN:generated-face-root.*?\*/(.*?)/\* END:generated-face-root \*/}m
    match = body.match(pattern)
    return "missing generated-face-root markers" unless match

    actual = match[1].strip
    expected = face_root_css
    return nil if actual == expected

    "face.css :root drift — run: ruby DEPLOY/rails/scripts/generate_face_root_css.rb"
  end
end