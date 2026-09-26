# frozen_string_literal: true

module Shared
  class FrontendRuleSet
    TYPOGRAPHY = {
      line_length: { min: 45, max: 75, ideal: 66, unit: "ch" },
      mobile_line_length: { min: 35, max: 50, unit: "ch" },
      body_line_height: { min: 1.4, max: 1.6 },
      heading_line_height: { min: 1.0, max: 1.2 },
      body_font_px: { min: 16 },
      all_caps_letter_spacing_em: { min: 0.05, max: 0.15 },
      max_font_families: 2,
      max_font_weights: 3,
      max_type_sizes: 8,
      max_selector_classes: 2,
      max_css_file_lines: 200,
    }.freeze

    SPACING = {
      base_unit: 8,
      scale: [ 4, 8, 16, 24, 32, 48, 64 ].freeze,
      touch_target_px: { min: 44, recommended: 48 },
    }.freeze

    PRESERVATION = {
      externalize_inline_css: true,
      externalize_inline_style_attributes: true,
      externalize_inline_javascript: true,
      preserve_existing_scss: true,
      preserve_keyframes: true,
      preserve_chartjs_config: true,
      preserve_font_faces: true,
      preserve_svg_assets: true,
      prefer_unified_diff_for_large_files: true,
      shell_scripts_must_not_embed_app_files: true,
      protected_stylesheet_files: %w[application.scss].freeze,
    }.freeze

    # Product pens: outside designs this tree reproduces exactly, shadows and
    # all — the yep.com search, the jsfiddle logo (jOxVvNE), Amazon's nav bar
    # and its animated logo. Hygiene checks leave them alone, and this is the one
    # place that says which CSS they are.
    #
    # The yep search is still a shared partial of its own, so its file names it.
    # The other three live inside each app's application.scss, so their
    # selectors name them: a rule is a pen when every selector in its list
    # styles one of these components.
    PRODUCT_PEN_FILES = %r{(?:\A|/)_search_yep\.scss\z}
    PRODUCT_PEN_SELECTORS = /
      \#(?:navBar|topHalf|sections|accountStuff|bottomHalf)\b
      | \.nav-(?:cart-count|search-submit)\b
      | \Abody\.vertical-marketplace\ (?:main\ >\ |\.marketplace-(?:deals|stores)\ >\ )?
          (?:\.search\b|\#live_search_results|\[data-controller\*="live-search"\])
      | :is\(body\.vertical-marketplace,\ body\.vertical-takeaway\)\ :is\(\.store-shortcut-well,\ \.store-buybox\)
      | \#logoWrapper\b | \.banner(?:_wrapper)?\b | \.smileyface\b | \.number_animate\b | \.shopping_cart\b
      | \.jox-logo\b | \Abody\ \.search\b
    /x

    MOTION = {
      max_transition_ms: 300,
      require_reduced_motion_override: true,
    }.freeze

    ACCESSIBILITY = {
      wcag_target: "aaa",
      normal_text_contrast: 7.0,
      touch_target_px: { min: 44, recommended: 48 },
      skip_to_main_required: true,
    }.freeze

    CODE = {
      max_method_lines: 20,
      max_parameters: 3,
      max_nesting: 3,
      require_guard_clauses: true,
      require_tracked_source_files: true,
    }.freeze

    def self.to_h
      {
        typography: TYPOGRAPHY,
        spacing: SPACING,
        preservation: PRESERVATION,
        motion: MOTION,
        accessibility: ACCESSIBILITY,
        code: CODE,
      }
    end
  end
end
