# frozen_string_literal: true

module Master
  module Design
    module Authority
      ORDER = %w[purpose agency clarity hierarchy trust consistency craft delight].freeze

      module_function

      def contract(root: Master::ROOT)
        Master.design("ultraminimalism", "authoritative_design", root:).tap do |value|
          raise KeyError, "authoritative_design: missing" unless value.is_a?(Hash)
        end
      end

      def school(name, root: Master::ROOT)
        Master.design("ultraminimalism", "design_schools", root:).fetch(name.to_s)
      end

      def schools(root: Master::ROOT)
        Master.design("ultraminimalism", "design_schools", root:)
      end

      def brief(path:, purpose:, school:, root: Master::ROOT)
        spec = contract(root:)
        "priority=#{spec.fetch("priority")} order=#{ORDER.join(">")} purpose=#{purpose} surface=#{path} school=#{school} proof=rendered_evidence_required"
      end
    end
  end
end
