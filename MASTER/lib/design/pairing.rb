# frozen_string_literal: true

module Master
  module Design
    module Pairing
      PURPOSES = {
        marketplace: "marketplace_sale",
        sale: "marketplace_sale",
        offer: "marketplace_sale",
        promotion: "marketplace_sale",
        editorial: "source_editorial",
        social: "swiss_house",
        cute: "playful_mona_hubot",
        toy: "playful_mona_hubot",
        terminal: "terminal_mono",
      }.freeze

      SCHOOL_DEFAULTS = {
        swiss: "swiss_house",
        commerce_editorial: "marketplace_sale",
        social: "swiss_house",
        cute: "playful_mona_hubot",
        industrial: "terminal_mono",
        luxury: "source_editorial",
        editorial: "source_editorial",
      }.freeze

      module_function

      def registry(root: Master::ROOT)
        Master.design("ultraminimalism", "font_pairings", root:) || {}
      end

      def fetch(name, root: Master::ROOT)
        registry(root:).fetch(name.to_s)
      end

      def for(school:, purpose: nil, root: Master::ROOT)
        key = purpose_key(purpose) || SCHOOL_DEFAULTS.fetch(school.to_sym)
        [key, fetch(key, root:)]
      end

      def candidates(school:, root: Master::ROOT)
        registry.filter_map do |name, spec|
          next unless spec.fetch("school").to_s == school.to_s
          next unless deployable?(spec, root:)

          [name, spec]
        end
      end

      def deployable?(spec, root: Master::ROOT)
        %w[display body price metadata].all? do |role|
          name = spec.fetch(role)
          Master::Design::Typeface.available?(name, shipped_only: true, root:)
        end && Master::Design::Typeface.compatible?(
          display: spec.fetch("display"),
          body: spec.fetch("body"),
          relationship: spec["strategy"],
          root:,
        )
      end

      def purpose_key(purpose)
        text = purpose.to_s.downcase
        PURPOSES.each { |key, value| return value if text.match?(/\b#{Regexp.escape(key)}\b/) }
        nil
      end

      def brief(school:, purpose: nil, root: Master::ROOT)
        key, spec = for(school:, purpose:, root:)
        "pairing=#{key} strategy=#{spec.fetch("strategy")} reference=#{spec.fetch("reference", "none")} intent=#{spec.fetch("typographic_intent", "functional")} display=#{spec.fetch("display")} body=#{spec.fetch("body")} price=#{spec.fetch("price")} metadata=#{spec.fetch("metadata")} deployable=#{deployable?(spec, root:)}"
      end
    end
  end
end
