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
      ].freeze

      module_function

      def ids
        IDS
      end

      def context
        load_laws!
        IDS.map { |id| format(id, Law.rules.fetch(id)) }.join("\n")
      end

      def load_laws!
        return if defined?(Law) && Law.rules.key?(IDS.first)

        require File.expand_path("../../law/law", __dir__)
        Law.load_all(File.expand_path("../../law", __dir__))
        missing = IDS.reject { |id| Law.rules.key?(id) }
        raise "visual usability law missing: #{missing.join(", ")}" unless missing.empty?
      end

      def format(id, law)
        "#{id}: #{law.ask} Fix: #{law.fix}"
      end
    end
  end
end
