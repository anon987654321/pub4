#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"
require_relative "master_design"
require_relative "../lib/trace/dmesg"

module DesignTokens
  ROOT = File.expand_path("../..", __dir__)
  SOURCE = File.join(ROOT, "MASTER", "data", "tokens.yml")
  ARTIFACT = File.join(ROOT, "RAILS", "__shared", "design_tokens.yml")
  FACE_ORDER = %w[c_text x_text c_accent c_danger c_code].freeze
  DIALECT_PATH = File.join(ROOT, "RAILS", "__shared", "app", "assets", "stylesheets", "_dialect_tokens.scss")

  # Explicit yml-key -> css-var maps for the values that have drifted before
  # (--color-warning, 2026-07-21: shared/_tokens.scss said #ffd400 while
  # every consuming app's own copy said #c9a227). Deliberately a hand-picked
  # list, not "every yml key" -- generation only ever corrects a value
  # that's already declared somewhere; it never invents a new property.
  SHARED_CHROME_MAP = {
    "color_success" => "color-success",
    "color_warning" => "color-warning",
    "color_info" => "color-info",
    "font" => "font",
    "font_code" => "font-mono",
    "transition_fast" => "transition-fast",
    "transition_normal" => "transition-normal",
    "ease_out" => "ease-out",
    "ease_spring" => "ease-spring",
  }.freeze

  VISUAL_IDENTITY_MAP = {
    "signal" => "pub4-signal",
    "signal_ink" => "pub4-signal-ink",
    "signal_on_light" => "pub4-signal-on-light",
    "display_size" => "text-display",
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

  TOKEN_MAPS = {
    "shared_chrome" => SHARED_CHROME_MAP,
    "luxury" => LUXURY_MAP,
    "visual_identity" => VISUAL_IDENTITY_MAP,
  }.freeze

  # amber is the wardrobe app and keeps its own luxury palette, set from its --amber-*
  # ink, muted and rule colours on a white page. The check and the sync both leave
  # these four properties in that one stylesheet alone, so a sync never repaints it.
  APP_OWNED_PALETTE = {
    "RAILS/amber/app/assets/stylesheets/application.scss" => %w[luxury-bg luxury-text luxury-muted luxury-border].freeze,
    "RAILS/amber/app/assets/stylesheets/_amber_late_product_finish.scss" => %w[luxury-bg luxury-text luxury-muted luxury-border].freeze,
  }.freeze

  module_function

  def read_utf8(path)
    File.read(path, encoding: "UTF-8")
  end

  def load
    Operator::MasterDesign.tokens(SOURCE)
  end

  def static_tokens_css
    tokens = load
    social = tokens.fetch("social")
    shared_chrome = tokens.fetch("shared_chrome")
    visual_identity = tokens.fetch("visual_identity")
    face_layout = tokens.fetch("face_root").fetch("layout")
    family = shared_chrome.fetch("font")

    <<~CSS
      /* Auto-synced by build_all_css.rb — social palette from design_tokens.yml */
      :root {
        color-scheme: dark;
        --bg: #{social.fetch("bg")};
        --surface: #{social.fetch("surface")};
        --surface-elevated: #{social.fetch("surface_elevated")};
        --search-bg: #{social.fetch("search_bg")};
        --text: #{social.fetch("text")};
        --text-secondary: #{social.fetch("text_secondary")};
        --border: #{social.fetch("border")};
        --hover: color-mix(in srgb, var(--text) 10%, transparent);
        --hover-subtle: color-mix(in srgb, var(--text) 3%, transparent);
        --accent: #{social.fetch("accent")};
        --danger: #{social.fetch("danger")};
        --pub4-signal: #{visual_identity.fetch("signal")};
        --pub4-signal-ink: #{visual_identity.fetch("signal_ink")};
        --pub4-signal-on-light: #{visual_identity.fetch("signal_on_light")};
        --text-display: #{visual_identity.fetch("display_size")};
        --font: #{family};
        --weight-normal: 400;
        --weight-medium: 500;
        --weight-bold: 700;
        --weight-heavy: 800;
        --radius-xs: #{social.fetch("radius_xs")};
        --radius-sm: #{social.fetch("radius_sm")};
        --radius-md: #{social.fetch("radius_md")};
        --radius-card: #{social.fetch("radius_card")};
        --radius-lg: #{social.fetch("radius_lg")};
        --radius-pill: #{social.fetch("radius_pill")};
        --transition-fast: #{shared_chrome.fetch("transition_fast")};
        --transition-normal: #{shared_chrome.fetch("transition_normal")};
        --z-chrome: #{face_layout.fetch("z-chrome")};
        --z-ui: #{face_layout.fetch("z-ui")};
        --z-overlay: #{face_layout.fetch("z-overlay")};
        --z-modal: #{face_layout.fetch("z-modal")};
        --z-toast: #{face_layout.fetch("z-toast")};
        --z-skip: #{face_layout.fetch("z-skip")};
        --color-background: var(--bg);
        --color-midtone: var(--text-secondary);
        --color-highlight: var(--surface);
        --color-accent: var(--accent);
        --color-border: var(--border);
        --text-primary: var(--text);
      }
      @media (prefers-color-scheme: light) {
        :root {
          color-scheme: light;
          --bg: #ffffff;
          --text: #0f1419;
          --text-secondary: #536471;
          --border: #eff3f4;
          --hover: color-mix(in srgb, var(--text) 10%, transparent);
          --hover-subtle: color-mix(in srgb, var(--text) 3%, transparent);
          --color-background: var(--bg);
          --color-highlight: var(--bg);
          --text-primary: var(--text);
        }
      }
    CSS
  end


  def face_root_css
    root = load
    data = root.fetch("face_root")
    anchors = data.fetch("anchors")
    derived = data.fetch("derived")
    layout = data.fetch("layout")
    visual_identity = root.fetch("visual_identity")
    # Face-local palette overrides keep the universal identity token and the
    # other product dialects independent. The rendered face remains monochrome.
    palette = data.fetch("palette", {})
    lines = [":root {",
             "  --pub4-signal: #{palette.fetch('signal', visual_identity.fetch('signal'))};",
             "  --pub4-signal-ink: #{palette.fetch('signal_ink', visual_identity.fetch('signal_ink'))};",
             "  --pub4-signal-on-light: #{palette.fetch('signal_on_light', visual_identity.fetch('signal_on_light'))};"]
    FACE_ORDER.each do |key|
      lines << "  --#{key.tr('_', '-')}: #{palette.fetch(key, anchors.fetch(key))};"
    end
    lines << "  --font-mono: #{data.fetch('font_mono')};"
    lines << "  --font-label: #{data.fetch('font_label')};"
    lines << "  color-scheme: dark;"
    %w[top right bottom left].each do |side|
      lines << "  --safe-#{side}: env(safe-area-inset-#{side}, 0px);"
    end
    # Read from the canonical design system; generated projections do not own values.
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

  def sync_design_artifact!(path = ARTIFACT)
    canonical = load
    actual = File.file?(path) ? YAML.safe_load_file(path, aliases: true) : nil
    return false if actual == canonical

    body = YAML.dump(canonical).sub(/\A---\n/, "")
    File.write(path, "# GENERATED from MASTER/data/tokens.yml. Do not edit by hand.\n#{body}")
    true
  end

  def vertical_accent_block
    data = load
    accents = data.fetch("vertical_accents")
    ink = data.fetch("vertical_accent_ink")
    lines = ["/* BEGIN:generated-vertical-accents — ruby MASTER/tools/design_tokens.rb sync_dialect_tokens */", "$vertical-accents: ("]
    # The fourth value is the ink painted on the accent: the vertical's own, or the shared one.
    accents.each do |name, values|
      lines << "  #{name}: (#{values.fetch('accent')}, #{values.fetch('hover')}, #{values.fetch('light')}, " \
               "#{values.fetch('ink', ink)}),"
    end
    lines << ");"
    lines << "$vertical-accent-ink: #{ink};"
    lines << "/* END:generated-vertical-accents */"
    lines.join("\n")
  end

  def sync_vertical_accents!(path = DIALECT_PATH)
    body = read_utf8(path)
    pattern = %r{/\* BEGIN:generated-vertical-accents.*?\*/.*?/\* END:generated-vertical-accents \*/}m
    updated = body.match?(pattern) ? body.sub(pattern, vertical_accent_block) : "#{vertical_accent_block}\n\n#{body}"
    return false if updated == body

    File.write(path, updated)
    true
  end

  # The dark :root of tokens.css, the family block master embeds ahead of its
  # own root. Only the dark half: the face is one-theme dark, and the light media
  # block would turn the chrome ink dark while the canvas stays black. Sliced
  # from static_tokens_css so the two can never hold different values.
  def family_tokens_block
    root = static_tokens_css[/^:root \{\n.*?^\}\n/m] || abort("design_tokens: tokens.css has no :root")

    "/* BEGIN:generated-family-tokens — the :root of RAILS/__shared/public/styles/tokens.css */\n" \
      "#{root}/* END:generated-family-tokens */"
  end

  def face_root_block
    <<~CSS.strip
      /* BEGIN:generated-face-root — ruby MASTER/tools/design_tokens.rb generate_face_root_css */
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

  def scss_anchor_drift?(path = File.join(ROOT, "RAILS", "__shared", "app", "assets", "stylesheets", "_dialect_tokens.scss"))
    return "missing #{path}" unless File.file?(path)

    scss = read_utf8(path)
    data = load
    face_anchors = data.fetch("face_root").fetch("anchors")
    social = data.fetch("social")
    drifted = []

    face_anchors.each do |key, value|
      # These are not all dialect defaults: the face's signal accent is an
      # intentional projection from visual_identity, not the palette mixin's
      # separate --c-accent default. The face root is generated directly from
      # the canonical anchor and cannot leak its identity into app dialects.
      next if %w[x_text c_accent].include?(key)

      needle = "$#{key.tr('_', '-')}: #{value}"
      drifted << "#{key}=#{value}" unless scss.include?(needle)
    end

    social_text = social.fetch("text")
    drifted << "text=#{social_text}" unless scss.include?("$text: #{social_text}")

    return if drifted.empty?

    "_dialect_tokens.scss defaults drifted from MASTER tokens anchors: #{drifted.join(', ')}"
  end

  def face_root_drift?(path)
    body = read_utf8(path)
    pattern = %r{/\* BEGIN:generated-face-root.*?\*/(.*?)/\* END:generated-face-root \*/}m
    match = body.match(pattern)
    return "missing generated-face-root markers" unless match

    actual = match[1].strip
    expected = face_root_css
    return if actual == expected

    "face.css :root drift — run: ruby MASTER/tools/design_tokens.rb generate_face_root_css"
  end

  # Every Rails app and mountable engine stylesheet participates in token
  # reconciliation. The one-level app glob missed RAILS/<app>/engines/* sources,
  # so a vertical could carry stale shared tokens without the drift check seeing it.
  # Vendor and built copies are artifacts, not sources to repair.
  def all_scss_files(root = ROOT)
    Dir.glob(File.join(root, "RAILS", "**", "app", "assets", "stylesheets", "**", "*.scss"))
      .reject { |path| path.match?(%r{/(?:vendor|node_modules|builds)/}) }
      .sort
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
    return unless m
    return if normalize(m[2]) == normalize(expected_value)

    "#{path.sub("#{ROOT}/", '')}: --#{css_var} is #{m[2].strip}, MASTER/data/tokens.yml says #{expected_value}"
  end

  # sync: true writes corrections and returns changed paths; sync: false
  # (the CI drift check) only reports, changing nothing.
  def reconcile_dialect_maps(sync:)
    data = load
    findings = []

    all_scss_files.each do |path|
      TOKEN_MAPS.each do |section, mappings|
        source = data.fetch(section, {})
        mappings.each do |yml_key, css_var|
          next unless source.key?(yml_key)

          next if app_owned?(path, css_var)

          expected = source[yml_key]
          if sync
            findings << "#{path.sub("#{ROOT}/", '')}: synced --#{css_var} -> #{expected}" if sync_property!(path, css_var, expected)
          else
            drift = property_drift(path, css_var, expected)
            findings << drift if drift
          end
        end
      end
    end
    findings
  end

  def app_owned?(path, css_var)
    APP_OWNED_PALETTE.fetch(path.sub("#{ROOT}/", ""), []).include?(css_var)
  end

  def sync_dialect_tokens! = reconcile_dialect_maps(sync: true)
  def dialect_token_drift = reconcile_dialect_maps(sync: false)
end

if $PROGRAM_NAME == __FILE__
  Master::Trace::Dmesg.status(
    "design0",
    DesignTokens.sync_design_artifact! ? "generated from MASTER/data/tokens.yml" : "already in sync",
  )
end
