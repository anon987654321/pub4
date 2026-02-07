# frozen_string_literal: true

module MASTER
  # Chamber - Multi-model deliberation with council personas
  # Implements multi-round debate: Independent → Synthesis → Convergence
  class Chamber
    MAX_ROUNDS = 25
    MAX_COST = 0.50
    CONSENSUS_THRESHOLD = 0.70
    CONVERGENCE_THRESHOLD = 0.05

    attr_reader :cost, :rounds, :proposals

    def initialize(llm: LLM)
      @llm = llm
      @cost = 0.0
      @rounds = 0
      @proposals = []
    end

    def arbiter_model
      LLM.model_tiers[:strong]&.first || "anthropic/claude-sonnet-4"
    end

    def self.council_review(text, model: nil)
      chamber = new(llm: LLM)
      chamber.council_review(text, text, model: model)
    end

    def deliberate(code, filename: "code", participants: %i[sonnet deepseek])
      @proposals = []
      @rounds = 0

      participants.each do |model_key|
        break if over_budget?

        model = MODELS[model_key]
        next unless model && @llm.circuit_closed?(model)

        proposal = propose(code, model, filename)
        @proposals << { model: model_key, proposal: proposal } if proposal
      end

      return Result.err("No proposals generated") if @proposals.empty?

      council_result = multi_round_review(code, @proposals.first[:proposal])

      arbiter_model = MODELS[ARBITER]
      if @llm.circuit_closed?(arbiter_model)
        final = arbiter_decision(code, @proposals, arbiter_model)
        Result.ok(
          original: code,
          proposals: @proposals,
          council: council_result,
          final: final,
          cost: @cost,
          rounds: @rounds,
        )
      else
        Result.ok(
          original: code,
          proposals: @proposals,
          council: council_result,
          final: @proposals.first[:proposal],
          cost: @cost,
          rounds: @rounds,
        )
      end
    end

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

    def propose(code, model, filename)
      @rounds += 1

      prompt = <<~PROMPT
        Review this code and propose improvements:
        FILE: #{filename}

        ```
        #{code[0, 4000]}
        ```

        Provide:
        1. ISSUES: What's wrong (bullet points)
        2. DIFF: Proposed changes (unified diff format)
        3. RATIONALE: Why these changes (one paragraph)
      PROMPT

      result = @llm.ask(prompt, model: model)
      return nil unless result.ok?

      data = result.value
      @cost += data[:cost] || 0

      data[:content]
    rescue StandardError
      @llm.open_circuit!(model)
      nil
    end

    def arbiter_decision(original, proposals, model)
      prompt = <<~PROMPT
        You are the arbiter. Given these proposals, pick the best changes:

        ORIGINAL:
        ```
        #{original[0, 2000]}
        ```

        PROPOSALS:
        #{proposals.map { |p| "#{p[:model]}:\n#{p[:proposal][0, 1000]}" }.join("\n\n")}

        Output ONLY the final improved code. No explanation.
      PROMPT

      result = @llm.ask(prompt, model: model)
      return proposals.first[:proposal] unless result.ok?

      data = result.value
      @cost += data[:cost] || 0

      data[:content]
    rescue StandardError
      proposals.first[:proposal]
    end

    def over_budget?
      @cost >= MAX_COST
    end

    # Creative mode: Brainstorm → Critique → Synthesize cycle
    # Merged from CreativeChamber
    def ideate(prompt:, constraints: [], cycles: 2)
      ideas = []
      critiques = []
      total_cost = 0

      cycles.times do
        # Brainstorm phase
        brainstorm = generate_ideas(prompt, ideas, constraints)
        return brainstorm if brainstorm.err?
        ideas += brainstorm.value[:ideas]
        total_cost += brainstorm.value[:cost]

        # Critique phase
        critique = critique_ideas(ideas)
        return critique if critique.err?
        critiques << critique.value[:critique]
        total_cost += critique.value[:cost]
      end

      # Synthesis phase
      synthesis = synthesize_ideas(prompt, ideas, critiques, constraints)
      return synthesis if synthesis.err?
      total_cost += synthesis.value[:cost]

      Result.ok(
        ideas: ideas,
        critiques: critiques,
        final: synthesis.value[:synthesis],
        cost: total_cost
      )
    end

    private

    def generate_ideas(prompt, existing_ideas, constraints)
      system_prompt = <<~SYS
        You are a creative visionary. Generate 3-5 novel ideas.
        Be bold, unconventional, surprising.
        Constraints to respect: #{constraints.join(', ')}
        #{"Previous ideas (don't repeat): #{existing_ideas.join(', ')}" if existing_ideas.any?}
      SYS

      full_prompt = "#{system_prompt}\n\nGenerate ideas for: #{prompt}"
      result = @llm.ask(full_prompt, tier: :strong)

      if result.ok?
        data = result.value
        content = data[:content].to_s
        parsed = content.scan(/^[\-\*•]\s*(.+)/).flatten
        parsed = [content] if parsed.empty?
        Result.ok(ideas: parsed, cost: data[:cost] || 0)
      else
        Result.err("Brainstorm failed: #{result.error}")
      end
    end

    def critique_ideas(ideas)
      critique_prompt = <<~PROMPT
        Critique these ideas honestly. What are the weaknesses, blind spots, implementation challenges?

        Ideas:
        #{ideas.map { |i| "- #{i}" }.join("\n")}
      PROMPT

      result = @llm.ask(critique_prompt, tier: :fast)

      if result.ok?
        data = result.value
        Result.ok(critique: data[:content], cost: data[:cost] || 0)
      else
        Result.err("Critique failed: #{result.error}")
      end
    end

    def synthesize_ideas(original_prompt, ideas, critiques, constraints)
      prompt = <<~PROMPT
        Original goal: #{original_prompt}
        Constraints: #{constraints.join(', ')}

        Ideas generated:
        #{ideas.map { |i| "- #{i}" }.join("\n")}

        Critiques:
        #{critiques.join("\n---\n")}

        Synthesize the best elements into a cohesive recommendation.
        Address the valid critiques.
        Be practical but preserve innovation.
      PROMPT

      result = @llm.ask(prompt, tier: :strong)

      if result.ok?
        data = result.value
        Result.ok(synthesis: data[:content], cost: data[:cost] || 0)
      else
        Result.err("Synthesis failed: #{result.error}")
      end
    end
  end
end
