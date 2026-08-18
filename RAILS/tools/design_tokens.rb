#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

module DesignTokens
  ROOT = File.expand_path("..", __dir__)
  SOURCE = File.join(ROOT, "shared", "design_tokens.yml")
  FACE_ORDER = %w[c_text x_text c_accent c_danger c_code].freeze

  # Explicit yml-key -> css-var maps for the values that have drifted before
  # (--color-warning, 2026-07-21: shared/_tokens.scss said #ffd400 while
  # every consuming app's own copy said #c9a227). Deliberately a hand-picked
  # list, not "every yml key" -- generation only ever corrects a value
  # that's already declared somewhere; it never invents a new property.
  SHARED_CHROME_MAP = {
    "color_success" => "color-success",
    "color_warning" => "color-warning",
    "color_info" => "color-info",
    "transition_fast" => "transition-fast",
    "transition_normal" => "transition-normal",
    "ease_out" => "ease-out",
    "ease_spring" => "ease-spring",
  }.freeze

  LUXURY_MAP = {
    "light_bg" => "luxury-bg",
    "light_surface" => "luxury-surface",
    "light_text" => "luxury-text",
    "light_muted" => "luxury-muted",
    "light_border" => "luxury-border",
    "light_accent" => "luxury-accent",
    "space_xs" => "luxury-space-xs",
    "space_sm" => "luxury-space-sm",
    "space_md" => "luxury-space-md",
    "space_lg" => "luxury-space-lg",
    "space_xl" => "luxury-space-xl",
    "radius_sm" => "luxury-radius-sm",
    "radius_md" => "luxury-radius-md",
    "radius_lg" => "luxury-radius-lg",
    "font_size_display" => "luxury-font-display",
    "font_size_title" => "luxury-font-title",
    "font_size_meta" => "luxury-font-meta",
    "letter_spacing_tight" => "luxury-letter-tight",
    "line_height_relaxed" => "luxury-line-relaxed",
  }.freeze

  module_function

  def read_utf8(path)
    File.read(path, encoding: "UTF-8")
  end

  def load
    YAML.safe_load_file(SOURCE) || {}
  end

  def face_root_css
    root = load
    data = root.fetch("face_root")
    anchors = data.fetch("anchors")
    derived = data.fetch("derived")
    layout = data.fetch("layout")
    lines = [":root {"]
    FACE_ORDER.each do |key|
      lines << "  --#{key.tr('_', '-')}: #{anchors.fetch(key)};"
    end
    lines << "  --font-mono: #{data.fetch('font_mono')};"
    lines << "  --font-label: #{data.fetch('font_label')};"
    lines << "  color-scheme: dark;"
    %w[top right bottom left].each do |side|
      lines << "  --safe-#{side}: env(safe-area-inset-#{side}, 0px);"
    end
    # Read, not restated. This line used to hardcode 0.75rem behind a comment
    # claiming it matched shared_chrome.chrome_inset — a copy describing itself
    # as a reference. When the token moved to 12px the face kept the old value
    # and the two drifted silently, which is the whole reason design_tokens.yml
    # exists.
    lines << "  --chrome-inset: #{root.fetch(%q{shared_chrome}).fetch(%q{chrome_inset})};"
    { "t" => "top", "r" => "right", "b" => "bottom", "l" => "left" }.each do |short, side|
      lines << "  --inset-#{short}: calc(var(--chrome-inset) + var(--safe-#{side}));"
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
      /* BEGIN:generated-face-root — ruby RAILS/tools/generate_face_root_css.rb */
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

  def scss_anchor_drift?(path = File.join(ROOT, "shared", "app", "assets", "stylesheets", "_dialect_tokens.scss"))
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

    social_text = social.fetch("text")
    drifted << "text=#{social_text}" unless scss.include?("$text: #{social_text}")

    return nil if drifted.empty?

    "_dialect_tokens.scss defaults drifted from design_tokens.yml anchors: #{drifted.join(', ')}"
  end

  def face_root_drift?(path)
    body = read_utf8(path)
    pattern = %r{/\* BEGIN:generated-face-root.*?\*/(.*?)/\* END:generated-face-root \*/}m
    match = body.match(pattern)
    return "missing generated-face-root markers" unless match

    actual = match[1].strip
    expected = face_root_css
    return nil if actual == expected

    "face.css :root drift — run: ruby RAILS/tools/generate_face_root_css.rb"
  end

  # Every .scss under RAILS/ -- deliberately broad, since the whole point is
  # that these values get hand-copied into per-app files (amber/_variables,
  # both _ui_refinements_pass.scss) rather than living in one place.
  def all_scss_files
    Dir.glob(File.join(ROOT, "*/app/assets/stylesheets/**/*.scss"))
  end

  def property_pattern(css_var)
    /(--#{Regexp.escape(css_var)}\s*:\s*)([^;]+)(;)/
  end

  # Only ever corrects a value already present at that property name in that
  # file -- never adds the property to a file that doesn't declare it.
  # Whitespace-insensitive so "cubic-bezier(0.25, 0.1)" (CSS convention)
  # and "cubic-bezier(0.25,0.1)" (yml's compact style) don't false-positive
  # as drift when the value is otherwise identical.
  def normalize(value) = value.to_s.gsub(/\s+/, "")

  def sync_property!(path, css_var, expected_value)
    body = read_utf8(path)
    pattern = property_pattern(css_var)
    return false unless (m = body.match(pattern))
    return false if normalize(m[2]) == normalize(expected_value)

    File.write(path, body.sub(pattern) { "#{m[1]}#{expected_value}#{m[3]}" })
    true
  end

  def property_drift(path, css_var, expected_value)
    body = read_utf8(path)
    m = body.match(property_pattern(css_var))
    return nil unless m
    return nil if normalize(m[2]) == normalize(expected_value)

    "#{path.sub("#{ROOT}/", '')}: --#{css_var} is #{m[2].strip}, design_tokens.yml says #{expected_value}"
  end

  # sync: true writes corrections and returns changed paths; sync: false
  # (the CI drift check) only reports, changing nothing.
  def reconcile_dialect_maps(sync:)
    data = load
    shared_chrome = data.fetch("shared_chrome", {})
    luxury = data.fetch("luxury", {})
    findings = []

    all_scss_files.each do |path|
      SHARED_CHROME_MAP.merge(LUXURY_MAP.transform_keys { |k| k }).each do |yml_key, css_var|
        source = SHARED_CHROME_MAP.key?(yml_key) ? shared_chrome : luxury
        next unless source.key?(yml_key)

        expected = source[yml_key]
        if sync
          findings << "#{path.sub("#{ROOT}/", '')}: synced --#{css_var} -> #{expected}" if sync_property!(path, css_var, expected)
        else
          drift = property_drift(path, css_var, expected)
          findings << drift if drift
        end
      end
    end
    findings
  end

  def sync_dialect_tokens! = reconcile_dialect_maps(sync: true)
  def dialect_token_drift = reconcile_dialect_maps(sync: false)
end
