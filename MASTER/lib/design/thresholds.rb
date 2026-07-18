# frozen_string_literal: true

module Master
  module Design
    # Loads data/design_rules.yml for scanners and UI critique.
    class Thresholds
      PATH = File.join(Master::DATA, "design_rules.yml").freeze

      def self.load(root: Master::ROOT)
        @cache ||= {}
        path = File.join(root, "data", "design_rules.yml")
        path = PATH unless File.file?(path)
        mtime = File.mtime(path).to_i
        hit = @cache[path]
        return hit[:data] if hit && hit[:mtime] == mtime

        data = Master.load_yaml(path, default: {}) || {}
        @cache[path] = { mtime: mtime, data: data }
        data
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Design::Thresholds.load")
        {}
      end

      def self.dig(*keys, root: Master::ROOT)
        load(root: root).dig(*keys)
      end

      def self.touch_min_px(root: Master::ROOT)
        dig("ux_laws", "fitts", "target_min_px", root: root) ||
          dig("layout_rules", "touch", "target_min_px", root: root) || 44
      end

      def self.max_visible_choices(root: Master::ROOT)
        dig("ux_laws", "hick", "max_visible_choices", root: root) || 7
      end

      def self.eight_px_rhythm(root: Master::ROOT)
        dig("pixel_perfection", "eight_px_rhythm", root: root) ||
          dig("layout_rules", "grid", "allowed_spacing_px", root: root) ||
          [0, 4, 8, 12, 16, 20, 24, 32, 40, 48, 64, 96]
      end

      def self.forbidden_css_patterns(root: Master::ROOT)
        patterns = Array(dig("pixel_perfection", "forbidden_patterns", root: root))
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
