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

        rules = Master.design("ultraminimalism", "typeface_rules", root:) || {}
        display_class = classification(display, root:)
        body_class = classification(body, root:)
        return true if relationship.to_s == "related_variable_family_pair"
        same_voice = display_class == body_class && x_height(display, root:) == x_height(body, root:)
        return false if same_voice && rules.fetch("avoid_same_voice_pairing", true)

        true
      end
    end
  end
end
