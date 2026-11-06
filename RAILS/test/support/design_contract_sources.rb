# frozen_string_literal: true

# The constants and readers design_contract_test.rb shares with the tests split
# out of it to keep each file under its length ceiling.
module DesignContractSources
  include StylesheetModules
  ROOT = File.expand_path("../..", __dir__)
  SHARED = File.join(ROOT, "__shared")
  DIALECT_TOKENS_SCSS = File.join(SHARED, "app", "assets", "stylesheets", "_dialect_tokens.scss")
  TOKENS_YML = File.join(SHARED, "design_tokens.yml")
  TOKENS_CSS = File.join(SHARED, "public", "styles", "tokens.css")
  TOKENS_SCSS = File.join(SHARED, "app", "assets", "stylesheets", "_tokens.scss")
  THEME_TOGGLE_JS = File.join(SHARED, "frontend", "theme_toggle_controller.js")
  BOTTOM_SHEET_JS = File.join(SHARED, "frontend", "bottom_sheet_controller.js")
  STIMULUS_BOOT_JS = File.join(SHARED, "frontend", "stimulus_boot.js")
  IMPORTMAP_BASELINE = File.join(SHARED, "config", "importmap_baseline.rb")
  MODAL_SCSS = File.join(SHARED, "app", "assets", "stylesheets", "_modal.scss")
  THEME_BOOTSTRAP = File.join(SHARED, "app", "views", "shared", "_theme_bootstrap.html.erb")
  ACTION_JS = File.join(SHARED, "frontend", "action_controller.js")
  ACTION_BAR = File.join(SHARED, "app", "views", "shared", "_action_bar.html.erb")
  ICON_PARTIAL = File.join(SHARED, "app", "views", "shared", "_icon.html.erb")
  ENGINE_RB = File.join(SHARED, "lib", "shared", "engine.rb")
  HOTWIRE_JS = File.join(SHARED, "frontend", "hotwire.js")
  FLEET_ROUTES = File.join(SHARED, "config", "routes", "fleet.rb")
  APPS = %w[amber brgen bsdports].freeze
  # Match real decorative depth, not "none" resets. Whitespace belongs inside
  # the lookahead so Ruby cannot backtrack past it and treat "none" as a value.
  # Flat UI also forbids blur/drop-shadow filters; semantic borders and outlines
  # carry separation and focus without a second visual language.
  FLAT_DESIGN_PATTERN = /
    box-shadow\s*:\s*(?!\s*none\b)
    | text-shadow\s*:\s*(?!\s*none\b)
    | backdrop-filter\s*:\s*(?!\s*none\b)
    | filter\s*:\s*[^;]*(?:\bblur\s*\(|\bdrop-shadow\s*\()
  /ix
  UI_STYLESHEET_EXCLUSIONS = %r{/(?:mrdamascy|vendor|builds|public/assets|node_modules)/}.freeze

  SCSS_PARAM_MAP = {
    "bg" => "bg",
    "surface" => "surface",
    "surface_elevated" => "surface-elevated",
    "text" => "text",
    "text_secondary" => "text-secondary",
    "border" => "border",
    "accent" => "accent",
    "danger" => "danger",
  }.freeze

  def app_rules(app)
    Operator::ScssRules.rules(stylesheet_source(app))
  end

  # --tap-min is 44px. A min-height/min-width written as the literal is the same
  # paint as the token and is how the floor drifted: half the family pointed at
  # the token and half restated the number. Use-sites must read the token;
  # definitions (`--tap-min: 44px`) and already-tokenised fallbacks stay.
  TAP_FLOOR_LITERAL = /(?<![\w-])(min-height|min-width|min-inline-size|min-block-size)\s*:\s*44px\b/
  TAP_FLOOR_SKIP = %r{/(builds|vendor|node_modules|public/assets)/}

  def mixin_block(scss, name)
    start = scss.index("@mixin #{name}")
    assert start, "missing @mixin #{name}"
    depth = 0
    i = start
    while i < scss.length
      depth += 1 if scss[i] == "{"
      if scss[i] == "}"
        depth -= 1
        return scss[start..i] if depth.zero? && i > start
      end
      i += 1
    end
    flunk "unclosed mixin #{name}"
  end

  def compiled_css_path(app)
    primary = File.join(ROOT, app, "app", "assets", "builds", "application.css")
    return primary if File.file?(primary)

    File.join(ROOT, app, "app", "assets", "builds", "app.css")
  end

  def tap_floor_stylesheets
    rails = Dir.glob(File.join(ROOT, "{*,#{EngineRoots::GLOB}}/app/assets/stylesheets/**/*.{scss,css}")) +
            Dir.glob(File.join(ROOT, "__shared/app/assets/stylesheets/**/*.{scss,css}")) +
            Dir.glob(File.join(ROOT, "__shared/frontend/**/*.css"))
    face = File.expand_path("../MASTER/web/public/face.css", ROOT)
    (rails + [face]).uniq.reject { |path| path.match?(TAP_FLOOR_SKIP) || !File.file?(path) }
  end
end
