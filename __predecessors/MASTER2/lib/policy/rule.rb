# frozen_string_literal: true

module MASTER
  module Policy
    # A single governance constraint, scoped to one or more modes.
    # severity: :hard  → blocks output on violation
    #           :soft  → warns but allows
    #           :contextual → caller decides
    class Rule
      attr_reader :id, :severity, :modes, :description

      def initialize(id:, severity:, modes:, description:, &checker)
        @id          = id
        @severity    = severity
        @modes       = Array(modes)
        @description = description
        @checker     = checker
      end

      def applies_to?(mode)
        @modes.include?(mode)
      end

      def evaluate(input:, output:)
        @checker.call(input, output)
      end
    end
  end
end
