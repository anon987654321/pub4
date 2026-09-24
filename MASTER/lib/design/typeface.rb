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
    end
  end
end
