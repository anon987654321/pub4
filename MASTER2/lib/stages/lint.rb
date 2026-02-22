# frozen_string_literal: true

module MASTER
  module Stages
    # Stage 7: Axiom enforcement
    class Lint
      REGEX_TIMEOUT = 0.1 # seconds

      def call(input)
        text = input[:response] || ""
        axioms = DB.axioms
        violations = []

        axioms.each do |axiom|
          pattern = axiom[:pattern]
          next unless pattern

          begin
            re = Regexp.new(pattern, Regexp::IGNORECASE)
            matched = Timeout.timeout(REGEX_TIMEOUT) { text.match?(re) }
            violations << axiom[:name] if matched
          rescue RegexpError, Timeout::Error
            # Skip invalid or pathological patterns
            next
          end
        end

        # Run NNG usability heuristics check if enabled
        design_violations = []
        if ENV["MASTER_CHECK_DESIGN"] == "true" && defined?(NNGChecklist)
          result = NNGChecklist.validate(text)
          design_violations = result.value if result.ok?
        end

        # Detect forbidden shell tools in generated shell code blocks
        zsh_violations = ZshPatternInjector.scan_violations(text)

        Result.ok(input.merge(
                    axiom_violations: violations,
                    zsh_violations: zsh_violations,
                    design_violations: design_violations,
                    linted: true,
                  ))
      end
    end
  end
end
