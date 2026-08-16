# frozen_string_literal: true

module Master
  module Design
    # The design_rules section of data/rules.yml, for scanners and UI critique.
    class Thresholds
      def self.load(root: Master::ROOT)
        Master.law("design_rules", root:)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Design::Thresholds.load")
        {}
      end

      def self.dig(*keys, root: Master::ROOT)
        load(root:).dig(*keys)
      end

      def self.touch_min_px(root: Master::ROOT)
        dig("ux_laws", "fitts", "target_min_px", root:) ||
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

      def self.eight_px_rhythm(root: Master::ROOT)
        dig("pixel_perfection", "eight_px_rhythm", root:) ||
          dig("layout_rules", "grid", "allowed_spacing_px", root:) ||
          [0, 4, 8, 12, 16, 20, 24, 32, 40, 48, 64, 96]
      end

      def self.forbidden_css_patterns(root: Master::ROOT)
        patterns = Array(dig("pixel_perfection", "forbidden_patterns", root:))
        return patterns unless patterns.empty?

        [
          /box-shadow\s*:/i,
          /text-shadow\s*:/i,
          /filter\s*:\s*[^;]*blur\s*\(/i,
          /backdrop-filter\s*:/i,
        ]
      end
    end
  end
end
