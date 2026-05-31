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
          metrics: { max_total_kb: 10, contrast: 4.5, line_min_ch: 45, line_max_ch: 75 }
        },
        medium: {
          philosophy: "long-form reading comfort through generous side whitespace and typographic rhythm",
          layout: %w[article_column max_65ch large_line_height restrained_navigation],
          avoid: %w[visual_noise dense_sidebars auto_play],
          metrics: { line_height: 1.58, max_width_px: 680 }
        },
        substack: {
          philosophy: "newsletter-first trust, direct author voice, low-friction subscription",
          layout: %w[publication_header readable_feed email_capture simple_article],
          avoid: %w[overdesigned_cards hidden_authors distracting_motion],
          metrics: { cta_count: 1, line_max_ch: 75 }
        },
        new_yorker: {
          philosophy: "editorial authority, strong type hierarchy, content as cultural object",
          layout: %w[serif_editorial strong_headlines generous_margins disciplined_grid],
          avoid: %w[cheap_gradients excessive_chrome noisy_cards],
          metrics: { contrast: 4.5, font_families_max: 2 }
        },
        x: {
          philosophy: "dense real-time feed optimized for scanning and interaction velocity",
          layout: %w[feed timeline compact_actions sticky_navigation],
          avoid: %w[slow_animation large_cards_hidden_content],
          metrics: { action_target_px: 44 }
        },
        tiktok: {
          philosophy: "full-screen media-first flow with minimal chrome and immediate feedback",
          layout: %w[full_screen_media vertical_flow gesture_first],
          avoid: %w[text_heavy_chrome slow_load blocking_modals],
          metrics: { first_frame_ms: 500 }
        }
      }.freeze

      module_function

      def fetch(name)
        PROFILES.fetch(name.to_sym)
      end

      def brief(name)
        p = fetch(name)
        parts = ["#{name}: #{p[:philosophy]}", "layout=#{p[:layout].join(', ')}",
          "avoid=#{p[:avoid].join(', ')}", "metrics=#{p[:metrics]}"]
        parts.join("; ")
      end

      def constraints(name)
        profile = fetch(name)
        [
          "philosophy: #{profile[:philosophy]}",
          "layout: #{profile[:layout].join(', ')}",
          "avoid: #{profile[:avoid].join(', ')}",
          "metrics: #{profile[:metrics]}"
        ]
      end

      def choose(text)
        source = text.to_s.downcase
        return :brutal_minimal if source.match?(/brutal|minimal|motherfucking|content-first|black.?white/)
        return :medium if source.include?("medium") || source.match?(/long.?form|reading/)
        return :substack if source.include?("substack") || source.include?("newsletter")
        return :new_yorker if source.include?("new yorker") || source.include?("editorial")
        return :tiktok if source.include?("tiktok") || source.include?("short video")
        return :x if source.match?(/\bx\b|twitter|feed/)

        :brutal_minimal
      end
    end
  end
end
