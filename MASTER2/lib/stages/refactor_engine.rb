# frozen_string_literal: true

module MASTER
  module Stages
    # Universal Refactor: Enforces axioms from axioms.yml
    class RefactorEngine
      def call(input)
        text = input[:text] || input[:original_text] || ""

        # Load axioms from DB
        protected_axioms = DB.get_axioms(protection: "PROTECTED")
        absolute_axioms = DB.get_axioms(protection: "ABSOLUTE")

        violations = []
        warnings = []

        # Check for ABSOLUTE axiom violations (these are errors)
        absolute_axioms&.each do |axiom|
          violation = check_axiom_violation(text, axiom)
          violations << violation if violation
        end

        # Check for PROTECTED axiom violations (these are warnings)
        protected_axioms&.each do |axiom|
          warning = check_axiom_violation(text, axiom)
          warnings << warning if warning
        end

        # Return error if ABSOLUTE axioms are violated
        return Result.err("ABSOLUTE axiom violation: #{violations.first}") unless violations.empty?

        # Add warnings to output
        enriched = input.merge(
          axiom_warnings: warnings,
          axioms_checked: true
        )

        Result.ok(enriched)
      end

      private

      def check_axiom_violation(text, axiom)
        # TODO: Implement actual AST analysis for code
        # For now, do simple pattern matching based on axiom ID

        case axiom["id"]
        when "DRY"
          # Check for repeated code patterns
          if text.scan(/def\s+\w+/).length > 10 && text.include?("copy")
            "Potential DRY violation: repeated patterns detected"
          end
        when "YAGNI"
          # Check for speculative code
          if text.match?(/\b(future|might|maybe|could)\b.*\b(need|use|want)\b/i)
            "Potential YAGNI violation: speculative functionality detected"
          end
        when "KISS"
          # Check for complexity indicators
          if text.length > 1000 && text.scan(/\bif\b/).length > 20
            "Potential KISS violation: high complexity detected"
          end
        else
          nil # No violation detected
        end
      end
    end
  end
end
