# frozen_string_literal: true

module MASTER
  module Stages
    class AdversarialReview
      def call(input)
        text = input[:text] || input[:original_text] || ""
        
        members = DB.council_members
        return Result.err("No council members found") if members.empty?

        threshold = (DB.config_value("council_consensus_threshold") || "0.70").to_f
        veto_precedence = (
          DB.config_value("council_veto_precedence") ||
          "security,attacker,maintainer"
        ).split(",")

        protected_axioms = DB.axioms(protection: "PROTECTED")
        absolute_axioms = DB.axioms(protection: "ABSOLUTE")

        violations = []
        warnings = []

        absolute_axioms&.each do |axiom|
          violation = axiom_violation(text, axiom)
          violations << violation if violation
        end

        protected_axioms&.each do |axiom|
          warning = axiom_violation(text, axiom)
          warnings << warning if warning
        end

        return Result.err("ABSOLUTE axiom violation: #{violations.first}") unless violations.empty?

        responses = []
        vetoes = []

        members.each do |member|
          response = {
            slug: member["slug"],
            name: member["name"],
            weight: member["weight"],
            veto: member["veto"] == 1,
            decision: :approve,
            reasoning: "Mock approval from #{member['name']}"
          }

          responses << response
          vetoes << response if response[:veto] && response[:decision] == :veto
        end

        unless vetoes.empty?
          veto = vetoes.first
          return Result.err("VETOED by #{veto[:name]}: #{veto[:reasoning]}")
        end

        approvals = responses.select { |r| r[:decision] == :approve }
        total_weight = approvals.sum { |r| r[:weight] }
        consensus_score = total_weight

        if consensus_score < threshold
          actual = (consensus_score * 100).round
          required = (threshold * 100).round
          return Result.err("Consensus not reached: #{actual}% < #{required}%")
        end

        enriched = input.merge(
          council_responses: responses,
          consensus_score: consensus_score,
          consensus_reached: true,
          axiom_warnings: warnings,
          axioms_checked: true
        )

        Result.ok(enriched)
      end

      private

      def axiom_violation(text, axiom)
        case axiom["id"]
        when "DRY"
          if text.scan(/def\s+\w+/).length > 10 && text.include?("copy")
            "Potential DRY violation: repeated patterns detected"
          end
        when "YAGNI"
          if text.match?(/\b(future|might|maybe|could)\b.*\b(need|use|want)\b/i)
            "Potential YAGNI violation: speculative functionality detected"
          end
        when "KISS"
          if text.length > 1000 && text.scan(/\bif\b/).length > 20
            "Potential KISS violation: high complexity detected"
          end
        else
          nil
        end
      end
    end
  end
end
