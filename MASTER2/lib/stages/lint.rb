# frozen_string_literal: true

require "json"

begin
  require "ruby_llm-tribunal"
rescue LoadError
  # ruby_llm-tribunal not available, fall back to regex heuristics
end

module MASTER
  module Stages
    # Universal Refactor: Enforces axioms from axioms.yml
    class Lint
      include Dry::Monads[:result]

      def call(input)
        text = input[:text] || input[:original_text] || ""

        # Load axioms from DB
        protected_axioms = DB.axioms(protection: "PROTECTED")
        absolute_axioms = DB.axioms(protection: "ABSOLUTE")

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
        return Failure("ABSOLUTE axiom violation: #{violations.first}") unless violations.empty?

        # Add warnings to output
        enriched = input.merge(
          axiom_warnings: warnings,
          axioms_checked: true
        )

        Success(enriched)
      end

      private

      def check_axiom_violation(text, axiom)
        # Try LLM-as-Judge first if available
        model = LLM.pick
        if model && defined?(RubyLLM::Tribunal)
          return check_with_llm(text, axiom, model)
        end
        
        # Fallback to regex heuristics
        check_with_regex(text, axiom)
      end
      
      def check_with_llm(text, axiom, model)
        prompt = <<~PROMPT
          Axiom: #{axiom["title"]} — #{axiom["statement"]}
          
          Does this text violate this axiom? Return JSON:
          {"violated": true/false, "reason": "one sentence explanation"}
          
          Text: #{text[0..2000]}
        PROMPT
        
        response = LLM.chat(model: model).ask(prompt)
        result = JSON.parse(response.content)
        
        # Track cost
        if response.respond_to?(:tokens_in) && response.respond_to?(:tokens_out)
          LLM.log_cost(
            model: model,
            tokens_in: response.tokens_in || 0,
            tokens_out: response.tokens_out || 0
          )
        end
        
        result["violated"] ? result["reason"] : nil
      rescue
        nil  # Can't check, don't block
      end
      
      def check_with_regex(text, axiom)
        # Simple pattern matching based on axiom ID
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
