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
      protected_stylesheet_files: %w[
        application.scss
        _dashboard.scss
        _vertical_dating.scss
        _vertical_playlist.scss
      ].freeze,
    }.freeze

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
