# frozen_string_literal: true

module Master
  module Fix
    module VisualUsability
      # The laws remain ONE_SOURCE in law/. This list only declares which
      # constitutional laws are relevant to rendered product review.
      IDS = %w[
        SYSTEM_STATUS
        MATCH_REAL_WORLD
        USER_CONTROL
        CONSISTENCY
        ERROR_RECOVERY
        AESTHETIC_MINIMALISM
        RECOGNITION_OVER_RECALL
        FLEXIBILITY_EFFICIENCY
        HELP_AND_DOCUMENTATION
        DENSITY
        PROXIMITY
        LINEARITY
        ABSTRACTION
        SINGULARITY
        STRONG_CENTERS
        LEVELS_OF_SCALE
        SQUINT_TEST
        BEAUTIFUL_CODE
        PSYCHOLOGICAL_ACCEPTABILITY
        PROGRESSIVE_DISCLOSURE
        FEEDBACK_LOOPS
        COST_TRANSPARENCY
        INTRINSIC_LAYOUT
        CONTAINER_RESPONSIVENESS
        MODERN_FORMS
        NATIVE_DISCLOSURE
        ANCHOR_RELATIONSHIPS
        SCOPED_CSS
        MOBILE_VIEWPORT
        SCROLL_INTEGRITY
        MOTION_ACCESSIBILITY
        NAVIGATION_CONTINUITY
      ].freeze

      module_function

      def ids
        IDS
      end

      def context
        load_laws!
        IDS.map { |id| line(id) }.join("\n")
      end

      # law/ keys its registry by symbol. DENSITY, PROXIMITY, LINEARITY,
      # ABSTRACTION and SINGULARITY are the axioms under rules.yml `laws:`, not
      # law/ files, so they are read from there.
      def load_laws!
        require File.expand_path("../../law/law", __dir__)
        Law.load_all(File.expand_path("../../law", __dir__)) unless Law.rules.key?(IDS.first.to_sym)
        missing = IDS.reject { |id| Law.rules.key?(id.to_sym) || axioms.key?(id) }
        raise "visual usability law missing: #{missing.join(", ")}" unless missing.empty?
      end

      def axioms
        @axioms ||= Master.load_yaml(Master::RULES_PATH).fetch("laws", {})
      end

      def line(id)
        law = Law.rules[id.to_sym]
        law ? "#{id}: #{law.ask} Fix: #{law.fix}" : "#{id}: #{axioms.fetch(id).fetch("principle")}"
      end
    end
  end
end
