# frozen_string_literal: true

module Master
  module Design
    module PlatformProfiles
      PROFILES = {
        brutal_minimal: {
          philosophy: "content-first, invisible design, delete anything that does not improve readability",
          layout: %w[single_column semantic_html system_fonts black_white max_65ch],
          avoid: %w[shadows glows gradients rounded_corners decorative_borders
            hero_banners loading_theatrics custom_fonts],
          metrics: { max_total_kb: 10, contrast: 4.5, line_min_ch: 45, line_max_ch: 75 },
        },
        medium: {
          philosophy: "long-form reading comfort through generous side whitespace and typographic rhythm",
          layout: %w[article_column max_65ch large_line_height restrained_navigation],
          avoid: %w[visual_noise dense_sidebars auto_play],
          metrics: { line_height: 1.58, max_width_px: 680 },
        },
        substack: {
          philosophy: "newsletter-first trust, direct author voice, low-friction subscription",
          layout: %w[publication_header readable_feed email_capture simple_article],
          avoid: %w[overdesigned_cards hidden_authors distracting_motion],
          metrics: { cta_count: 1, line_max_ch: 75 },
        },
        new_yorker: {
          philosophy: "editorial authority, strong type hierarchy, content as cultural object",
          layout: %w[serif_editorial strong_headlines generous_margins disciplined_grid],
          avoid: %w[cheap_gradients excessive_chrome noisy_cards],
          metrics: { contrast: 4.5, font_families_max: 2 },
        },
        x: {
          philosophy: "dense real-time feed optimized for scanning and interaction velocity",
          layout: %w[feed timeline compact_actions sticky_navigation],
          avoid: %w[slow_animation large_cards_hidden_content],
          metrics: { action_target_px: 44 },
        },
        tiktok: {
          philosophy: "full-screen media-first flow with minimal chrome and immediate feedback",
          layout: %w[full_screen_media vertical_flow gesture_first],
          avoid: %w[text_heavy_chrome slow_load blocking_modals],
          metrics: { first_frame_ms: 500 },
        },
      }.freeze

      module_function

      def fetch(name)
        PROFILES.fetch(name.to_sym)
      end

      def brief(name)
        profile = fetch(name)
        parts = ["#{name}: #{profile[:philosophy]}", "layout=#{profile[:layout].join(', ')}",
          "avoid=#{profile[:avoid].join(', ')}", "metrics=#{profile[:metrics]}"]
        parts.join("; ")
      end

      def constraints(name)
        profile = fetch(name)
        [
          "philosophy: #{profile[:philosophy]}",
          "layout: #{profile[:layout].join(', ')}",
          "avoid: #{profile[:avoid].join(', ')}",
          "metrics: #{profile[:metrics]}",
        ]
      end

      def choose(text)
        source = text.to_s.downcase
        return :brutal_minimal if source.match?(/brutal|minimal|motherfucking|content-first|black.?white/)
        return :substack if source.include?("substack") || source.include?("newsletter")
        return :tiktok if source.include?("tiktok") || source.include?("short video")

        :brutal_minimal
      end
    end

    # The design-tier rules of data/rules.yml, for scanners and UI critique.
    class Thresholds
      def self.load(root: Master::ROOT)
        Master.design_rules(root:)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Design::Thresholds.load")
        {}
      end

      def self.dig(*keys, root: Master::ROOT)
        load(root:).dig(*keys)
      end

      # `dig` is private because every key worth reading has a named accessor
      # below, and a bare dig from outside is how a second spelling of the same
      # threshold gets introduced.
      #
      # `load` is public because the section is also read wholesale: the voice
      # personality builds one prompt line per design concern and wants the
      # whole hash, not eight separate calls. Making it private satisfies an
      # abstraction count and breaks that caller, and a private method with two
      # callers outside the class is not an abstraction — it is an outage.
      private_class_method :dig

      def self.touch_min_px(root: Master::ROOT)
        # layout_rules.touch and ux_laws.fitts are one YAML value (&touch_min_px).
        dig("layout_rules", "touch", "target_min_px", root:) || 44
      end

      def self.max_visible_choices(root: Master::ROOT)
        dig("ux_laws", "hick", "max_visible_choices", root:) || 7
      end

      def self.worn_type(root: Master::ROOT)
        dig("worn_type", root:) || {}
      end

      def self.worn_profile(name, root: Master::ROOT)
        profiles = worn_type(root:)["profiles"] || {}
        feed = profiles["feed"] || {}
        spec = profiles[name.to_s] || {}
        feed.merge(spec).merge("name" => name.to_s)
      end

      def self.allowed_line_heights(root: Master::ROOT)
        raw = dig("typography", "line_height", "allowed", root:)
        return raw.map(&:to_f) if raw.is_a?(Array) && !raw.empty?

        # Same steps as RAILS/shared/design_tokens.yml scale.line_height / ScaleLint
        [1.0, 1.25, 1.4, 1.5, 1.6]
      end

      def self.body_line_height_preferred(root: Master::ROOT)
        dig("typography", "line_height", "body_preferred", root:) || 1.5
      end

      def self.measure_ideal_ch(root: Master::ROOT)
        dig("typography", "optical_margins", "measure_ideal_ch", root:) ||
          dig("typography", "line_length", "ideal_ch", root:) || 66
      end

      def self.micro_typography(root: Master::ROOT)
        dig("typography", "micro", root:) || {}
      end

      def self.eight_px_rhythm(root: Master::ROOT)
        # pixel_perfection.eight_px_rhythm aliases layout_rules.grid.allowed_spacing_px.
        dig("pixel_perfection", "eight_px_rhythm", root:) ||
          [0, 4, 8, 12, 16, 20, 24, 32, 40, 44, 48, 64, 96]
      end
    end
  end
end
