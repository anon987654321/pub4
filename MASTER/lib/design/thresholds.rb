# frozen_string_literal: true

module Master
  module Design
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

      def self.micro_typography(root: Master::ROOT)
        dig("typography", "micro", root:) || {}
      end

      def self.eight_px_rhythm(root: Master::ROOT)
        dig("pixel_perfection", "eight_px_rhythm", root:) ||
          dig("layout_rules", "grid", "allowed_spacing_px", root:) ||
          [0, 4, 8, 12, 16, 20, 24, 32, 40, 48, 64, 96]
      end
    end
  end
end
