# frozen_string_literal: true

module Master
  module Design
    module Composition
      module_function

      def registry(root: Master::ROOT)
        Master.design("ultraminimalism", "compositions", root:) || {}
      end

      def fetch(name, root: Master::ROOT)
        registry(root:).fetch(name.to_s)
      end

      def for(school:, purpose: nil, root: Master::ROOT)
        key = composition_key(school:, purpose:)
        [key, fetch(key, root:)]
      end

      def variants(name = "marketplace_sale", root: Master::ROOT)
        spec = fetch(name, root:)
        Hash(spec.fetch("variants", {}))
      end

      def variant(name:, variant: nil, root: Master::ROOT)
        rows = variants(name, root:)
        key = variant.to_s
        key = rows.keys.first if key.empty?
        [key, rows.fetch(key)]
      end

      def brief(school:, purpose: nil, root: Master::ROOT)
        key, spec = Composition.for(school:, purpose:, root:)
        variants = spec.fetch("variants", {})
        summary = variants.map { |name, value| "#{name}:#{value.fetch("reference")}/#{value.fetch("structure")}" }
        suffix = summary.empty? ? "" : " variants=#{summary.join(",")}"
        "composition=#{key} grid=#{spec.fetch("grid")} mobile=#{spec.fetch("mobile")} focal_order=#{Array(spec.fetch("focal_order")).join(">")}#{suffix}"
      end

      def composition_key(school:, purpose:)
        text = purpose.to_s.downcase
        return "marketplace_sale" if school.to_sym == :commerce_editorial && text.match?(/market|sale|offer|promotion|listing|shop/)
        return "swiss_poster" if school.to_sym == :swiss
        return "social_feed" if school.to_sym == :social
        return "cute_retail" if school.to_sym == :cute
        return "industrial_system" if school.to_sym == :industrial

        "editorial_commerce"
      end
    end
  end
end
