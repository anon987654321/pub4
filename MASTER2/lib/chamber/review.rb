# frozen_string_literal: true

module MASTER
  class Council
    # Council review methods - multi-round deliberation with persona voting
    module Review
      # Multi-round review with convergence tracking
      def multi_round_review(original, proposal)
        personas = DB.council
        return { passed: true, votes: [], vetoed_by: [], rounds: 0 } if personas.empty?

        all_rounds = []
        previous_consensus = 0.0
        final_result = nil

        MAX_ROUNDS.times do |round_num|
          break if over_budget?

          round_result = council_review(original, proposal, model: nil)
          all_rounds << round_result

          if round_result[:vetoed_by]&.any?
            return round_result.merge(rounds: round_num + 1, all_rounds: all_rounds)
          end

          current_consensus = round_result[:consensus] || 0
          delta = (current_consensus - previous_consensus).abs

          if round_num > 0 && delta < CONVERGENCE_THRESHOLD
            return round_result.merge(
              rounds: round_num + 1,
              converged: true,
              all_rounds: all_rounds,
            )
          end

          if current_consensus >= CONSENSUS_THRESHOLD
            return round_result.merge(rounds: round_num + 1, all_rounds: all_rounds)
          end

          if round_num < MAX_ROUNDS - 1 && !over_budget?
            proposal = synthesize(proposal, round_result[:votes])
          end

          previous_consensus = current_consensus
          final_result = round_result
        end

        (final_result || {}).merge(
          rounds: MAX_ROUNDS,
          converged: false,
          halted: true,
          all_rounds: all_rounds,
        )
      end

      # Single round of council review with persona voting
      def council_review(original, proposal, model: nil)
        personas = DB.council
        return { passed: true, votes: [], vetoed_by: [] } if personas.empty?

        votes = []
        vetoed_by = []
        veto_personas = personas.select { |p| p[:veto] }
        advisory_personas = personas.reject { |p| p[:veto] }

        veto_personas.first(3).each do |persona|
          break if over_budget?
          vote = get_persona_vote(persona, original, proposal)
          votes << vote
          if vote[:veto]
            vetoed_by << persona[:name]
            return { passed: false, verdict: :rejected, vetoed_by: vetoed_by, votes: votes }
          end
        end

        advisory_personas.first(3).each do |persona|
          break if over_budget?
          votes << get_persona_vote(persona, original, proposal)
        end

        total_weight = votes.sum { |v| v[:weight] || 0.1 }
        approve_weight = votes.select { |v| v[:approve] }.sum { |v| v[:weight] || 0.1 }
        consensus = total_weight > 0 ? (approve_weight / total_weight) : 0

        {
          passed: consensus >= CONSENSUS_THRESHOLD,
          verdict: consensus >= CONSENSUS_THRESHOLD ? :approved : :rejected,
          consensus: consensus.round(2),
          vetoed_by: [],
          votes: votes,
        }
      end

      private

      # Synthesize proposal based on council feedback
      def synthesize(proposal, votes)
        rejections = votes.select { |v| !v[:approve] }
        return proposal if rejections.empty? || over_budget?

        concerns = rejections.map { |v| "#{v[:name]}: #{v[:reason]}" }.join("\n")

        prompt = <<~PROMPT
          The council raised these concerns about the proposal:

          #{concerns}

          CURRENT PROPOSAL (first 1500 chars):
          #{proposal[0, 1500]}

          Revise the proposal to address these concerns.
          Output ONLY the revised proposal, no explanation.
        PROMPT

        result = @llm.ask(prompt, tier: :fast)
        return proposal unless result.ok?

        data = result.value
        @cost += data[:cost] || 0
        @rounds += 1

        data[:content]
      rescue StandardError => e
        DB.append("errors", { context: "chamber_synthesize", error: e.message, time: Time.now.utc.iso8601 })
        proposal
      end

      # Get individual persona vote on a proposal
      def get_persona_vote(persona, original, proposal)
        return { name: persona[:name], approve: true, weight: persona[:weight] || 0.1 } if over_budget?

        prompt = <<~PROMPT
          You are #{persona[:name]}.
          #{persona[:directive] || persona[:style]}

          Review this proposed change:

          ORIGINAL (first 500 chars):
          #{original[0, 500]}

          PROPOSED (first 500 chars):
          #{proposal[0, 500]}

          Respond with ONLY one word: APPROVE or REJECT
          Then one sentence explaining why.
        PROMPT

        result = @llm.ask(prompt, tier: :fast)
        return { name: persona[:name], approve: true, weight: persona[:weight] || 0.1 } unless result.ok?

        data = result.value
        @cost += data[:cost] || 0

        content = data[:content].to_s.strip
        approve = content.upcase.start_with?("APPROVE")
        veto = persona[:veto] && content.upcase.start_with?("REJECT")

        {
          name: persona[:name],
          approve: approve,
          veto: veto,
          weight: persona[:weight] || 0.1,
          reason: content.split("\n").last,
        }
      rescue StandardError => e
        DB.append("errors", { context: "chamber_vote", persona: persona[:name], error: e.message, time: Time.now.utc.iso8601 })
        { name: persona[:name], approve: true, weight: persona[:weight] || 0.1 }
      end
    end
  end
end
