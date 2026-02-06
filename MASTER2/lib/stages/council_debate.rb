# frozen_string_literal: true

module MASTER
  module Stages
    # Adversarial Council: Multi-persona debate with veto logic
    class CouncilDebate
      def call(input)
        text = input[:text] || input[:original_text] || ""
        
        # Load council members from DB
        members = DB.get_council_members
        return Result.err("No council members found") if members.empty?

        # Load council parameters
        threshold = (DB.get_config("council_consensus_threshold") || "0.70").to_f
        veto_precedence = (DB.get_config("council_veto_precedence") || "security,attacker,maintainer").split(",")

        # Collect responses from each persona (stubbed for now with TODOs)
        responses = []
        vetoes = []

        members.each do |member|
          # TODO: Make actual LLM call with persona directive
          # For now, simulate approval with mock data
          response = {
            slug: member["slug"],
            name: member["name"],
            weight: member["weight"],
            veto: member["veto"] == 1,
            decision: :approve, # Stubbed: would be :approve, :reject, or :veto
            reasoning: "Mock approval from #{member['name']}"
          }

          responses << response
          vetoes << response if response[:veto] && response[:decision] == :veto
        end

        # Check for vetoes (precedence order matters)
        unless vetoes.empty?
          veto = vetoes.first
          return Result.err("VETOED by #{veto[:name]}: #{veto[:reasoning]}")
        end

        # Calculate weighted consensus
        approvals = responses.select { |r| r[:decision] == :approve }
        total_weight = approvals.sum { |r| r[:weight] }
        consensus_score = total_weight

        if consensus_score < threshold
          return Result.err("Consensus not reached: #{(consensus_score * 100).round}% < #{(threshold * 100).round}%")
        end

        # Merge council recommendations into output
        enriched = input.merge(
          council_responses: responses,
          consensus_score: consensus_score,
          consensus_reached: true
        )

        Result.ok(enriched)
      end
    end
  end
end
