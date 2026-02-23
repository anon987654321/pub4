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

          return round_result.merge(rounds: round_num + 1, all_rounds: all_rounds) if round_result[:vetoed_by]&.any?

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

          proposal = synthesize(proposal, round_result[:votes]) if round_num < MAX_ROUNDS - 1 && !over_budget?

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
        return { passed: true, votes: [], vetoed_by: [], thread: [] } if personas.empty?

        votes    = []
        vetoed_by = []
        thread   = [] # shared deliberation — each model reads prior voices before speaking

        personas.each do |persona|
          break if over_budget?

          vote = get_persona_vote(persona, original, proposal, thread: thread)
          votes << vote
          thread << { name: vote[:name], model: persona[:model], feedback: vote[:reason] }

          if vote[:veto]
            vetoed_by << vote[:name]
            return { passed: false, verdict: :rejected, vetoed_by: vetoed_by, votes: votes, thread: thread }
          end
        end

        total_weight   = votes.sum { |v| v[:weight] || 0.1 }
        approve_weight = votes.select { |v| v[:approve] }.sum { |v| v[:weight] || 0.1 }
        consensus      = total_weight > 0 ? (approve_weight / total_weight) : 0

        {
          passed:    consensus >= CONSENSUS_THRESHOLD,
          verdict:   consensus >= CONSENSUS_THRESHOLD ? :approved : :rejected,
          consensus: consensus.round(2),
          vetoed_by: [],
          votes:     votes,
          thread:    thread,
        }
      end

      private

      # Synthesize proposal based on council feedback
      def synthesize(proposal, votes)
        rejections = votes.reject { |v| v[:approve] }
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
        DB.log_error(context: "chamber_synthesize", error: e.message)
        proposal
      end

      # Get individual persona vote, aware of the deliberation thread so far
      def get_persona_vote(persona, original, proposal, thread: [])
        return { name: persona[:name], approve: true, weight: persona[:weight] || 0.1 } if over_budget?

        is_devils_advocate = !persona[:veto] && (@cost * 10).to_i.odd?
        dissent_nudge = if is_devils_advocate
          "\nYour role this round is DEVIL'S ADVOCATE. Actively seek flaws and reasons to REJECT."
        else
          ""
        end

        thread_section = if thread.any?
          prior = thread.map { |t| "#{t[:name]} (#{t[:model] || 'unknown'}): #{t[:feedback]}" }.join("\n")
          <<~THREAD
            DELIBERATION SO FAR — read this before forming your view:
            #{prior}

          THREAD
        else
          ""
        end

        prompt = <<~PROMPT
          You are #{persona[:name]}.
          #{persona[:directive] || persona[:style]}#{dissent_nudge}

          #{thread_section}ORIGINAL (first 500 chars):
          #{original[0, 500]}

          PROPOSED (first 500 chars):
          #{proposal[0, 500]}

          You have read what your colleagues said above. Now give YOUR independent assessment.
          Respond with ONLY one word: APPROVE or REJECT
          Then one sentence explaining your reasoning, referencing prior feedback if relevant.
        PROMPT

        ask_opts = persona[:model] ? { model: persona[:model] } : { tier: :fast }
        result   = @llm.ask(prompt, **ask_opts)
        return { name: persona[:name], approve: true, weight: persona[:weight] || 0.1 } unless result.ok?

        data    = result.value
        @cost  += data[:cost] || 0

        content = data[:content].to_s.strip
        verdict = content.upcase.split.first  # APPROVE / REJECT / PRAISE
        praise  = verdict == "PRAISE"
        approve = verdict == "APPROVE" || praise
        veto    = persona[:veto] && verdict == "REJECT"

        # Register praise votes as exemplars
        if praise && defined?(BeautyScorer)
          BeautyScorer.register_exemplar(
            name:   "council:#{persona[:name]}",
            file:   "chamber/review",
            score:  5,
            virtue: :council_praise,
            why:    content.lines.last&.strip,
          )
        end

        {
          name:    persona[:name],
          model:   persona[:model],
          approve: approve,
          praise:  praise,
          veto:    veto,
          weight:  persona[:weight] || 0.1,
          reason:  content.lines.last&.strip,
        }
      rescue StandardError => e
        DB.log_error(context: "chamber_vote", error: e.message, persona: persona[:name])
        { name: persona[:name], approve: true, weight: persona[:weight] || 0.1 }
      end
    end
  end
end
