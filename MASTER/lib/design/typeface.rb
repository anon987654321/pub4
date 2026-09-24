# frozen_string_literal: true

module Master
  module Design
    module Typeface
      module_function

      def registry(root: Master::ROOT)
        Master.design("ultraminimalism", "typefaces", root:) || {}
      end

      def fetch(name, root: Master::ROOT)
        registry(root:).fetch(name.to_s)
      end

      def css(name, root: Master::ROOT)
        fetch(name, root:).fetch("css")
      end

      def available?(name, shipped_only: false, root: Master::ROOT)
        value = fetch(name, root:).fetch("availability")
        shipped_only ? value == "shipped" : %w[shipped optional_webfont].include?(value)
      end

      def roles(name, root: Master::ROOT)
        Array(fetch(name, root:)["roles"]).map(&:to_s)
      end

      def classification(name, root: Master::ROOT)
        fetch(name, root:).fetch("classification").to_s
      end

      def x_height(name, root: Master::ROOT)
        fetch(name, root:).fetch("x_height").to_s
      end

      def compatible?(display:, body:, relationship: nil, root: Master::ROOT)
        return true if display.to_s == body.to_s
        return false unless available?(display, root:) && available?(body, root:)

        display_class = classification(display, root:)
        body_class = classification(body, root:)
        return true if relationship.to_s == "related_variable_family_pair"
        return false if display_class == body_class && x_height(display, root:) == x_height(body, root:)

        true
      end

      def metric_snapshot(name, root: Master::ROOT)
        spec = fetch(name, root:)
        {
          family: spec.fetch("family"),
          classification: spec.fetch("classification"),
          x_height: spec["x_height"],
          width: spec["width"],
          contrast: spec["contrast"],
          weight_range: spec["weight_range"],
          optical_sizing: spec["optical_sizing"],
          availability: spec.fetch("availability"),
        }
      end
    end
  end
end
