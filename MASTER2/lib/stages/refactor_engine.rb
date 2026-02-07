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
        when "STRUCTURAL_MERGE"
          defs = text.scan(/def\s+(\w+)/).flatten
          duplicates = defs.select { |d| defs.count(d) > 1 }.uniq
          "Potential STRUCTURAL_MERGE violation: duplicate definitions: #{duplicates.join(", ")}" unless duplicates.empty?
        when "STRUCTURAL_FLATTEN"
          max_indent = text.each_line.map { |l| l[/\A\s*/].length }.max || 0
          "Potential STRUCTURAL_FLATTEN violation: nesting depth #{max_indent / 2} levels" if max_indent > 12
        when "STRUCTURAL_HOIST"
          if text.match?(/\b(each|map|select|reject|loop|while|until)\b.*\b(require|load|read|query|fetch)\b/m)
            "Potential STRUCTURAL_HOIST violation: I/O or loading inside iteration"
          end
        when "STRUCTURAL_COALESCE"
          lines = text.each_line.to_a
          sequential = lines.each_cons(2).count { |a, b| a.strip.start_with?("DB.") && b.strip.start_with?("DB.") }
          "Potential STRUCTURAL_COALESCE violation: #{sequential} sequential DB operations" if sequential > 2
        when "STRUCTURAL_PRUNE"
          if text.match?(/# (TODO|FIXME|HACK|XXX|DEAD|UNUSED):/i)
            "Potential STRUCTURAL_PRUNE violation: dead/unused code markers found"
          end
        else
          nil # No violation detected
        end
      end
    end
  end
end
