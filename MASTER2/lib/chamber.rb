# frozen_string_literal: true

module MASTER
  # Chamber - Multi-model deliberation with council personas
  # Implements multi-round debate: Independent → Synthesis → Convergence
  class Chamber
    MODELS = {
      sonnet: "anthropic/claude-sonnet-4",
      deepseek: "deepseek/deepseek-r1",
      gpt: "openai/gpt-4.1-mini",
    }.freeze

    ARBITER = :sonnet
    MAX_ROUNDS = 25          # Max iterations before forced halt
    MAX_COST = 0.50
    CONSENSUS_THRESHOLD = 0.70
    CONVERGENCE_THRESHOLD = 0.05  # Stop if opinions change < 5%

    attr_reader :cost, :rounds, :proposals

    def initialize(llm: LLM)
      @llm = llm
      @cost = 0.0
      @rounds = 0
      @proposals = []
    end

    # Class method for stage integration
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

      # Run through multi-round council review
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

    # Multi-round council review with convergence detection
    def multi_round_review(original, proposal)
      personas = DB.council
      return { passed: true, votes: [], vetoed_by: [], rounds: 0 } if personas.empty?

      all_rounds = []
      previous_consensus = 0.0
      final_result = nil

      MAX_ROUNDS.times do |round_num|
        break if over_budget?

        # Phase 1: Independent voting
        round_result = council_review(original, proposal, model: nil)
        all_rounds << round_result

        # Check for veto
        if round_result[:vetoed_by]&.any?
          return round_result.merge(rounds: round_num + 1, all_rounds: all_rounds)
        end

        # Check for convergence
        current_consensus = round_result[:consensus] || 0
        delta = (current_consensus - previous_consensus).abs

        if round_num > 0 && delta < CONVERGENCE_THRESHOLD
          # Converged - no significant opinion change
          return round_result.merge(
            rounds: round_num + 1,
            converged: true,
            all_rounds: all_rounds,
          )
        end

        # Check if consensus reached
        if current_consensus >= CONSENSUS_THRESHOLD
          return round_result.merge(rounds: round_num + 1, all_rounds: all_rounds)
        end

        # Phase 2: Synthesis - share votes and let personas revise
        if round_num < MAX_ROUNDS - 1 && !over_budget?
          proposal = synthesize(proposal, round_result[:votes])
        end

        previous_consensus = current_consensus
        final_result = round_result
      end

      # Max rounds reached without consensus
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

      # Veto holders review first
      veto_personas.first(3).each do |persona|
        break if over_budget?
        vote = get_persona_vote(persona, original, proposal)
        votes << vote
        # Veto blocks immediately
        if vote[:veto]
          vetoed_by << persona[:name]
          return { passed: false, verdict: :rejected, vetoed_by: vetoed_by, votes: votes }
        end
      end

      # Advisory personas
      advisory_personas.first(3).each do |persona|
        break if over_budget?
        votes << get_persona_vote(persona, original, proposal)
      end

      # Calculate weighted consensus
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

    # Synthesis phase: incorporate feedback into proposal
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

      model = @llm.select_available_model
      return proposal unless model

      chat = @llm.chat(model: model)
      response = chat.ask(prompt)

      tokens_in = response.input_tokens || 0
      tokens_out = response.output_tokens || 0
      @cost += @llm.record_cost(model: model, tokens_in: tokens_in, tokens_out: tokens_out)
      @rounds += 1

      response.content
    rescue StandardError => e
      DB.append("errors", { context: "chamber_synthesize", error: e.message, time: Time.now.utc.iso8601 })
      proposal
    end

    def get_persona_vote(persona, original, proposal)
      return { name: persona[:name], approve: true, weight: persona[:weight] || 0.1 } if over_budget?

      model = @llm.select_available_model
      return { name: persona[:name], approve: true, weight: persona[:weight] || 0.1 } unless model

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

      chat = @llm.chat(model: model)
      response = chat.ask(prompt)

      tokens_in = response.input_tokens || 0
      tokens_out = response.output_tokens || 0
      @cost += @llm.record_cost(model: model, tokens_in: tokens_in, tokens_out: tokens_out)

      content = response.content.to_s.strip
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

      chat = @llm.chat(model: model)
      response = chat.ask(prompt)

      tokens_in = response.input_tokens rescue 0
      tokens_out = response.output_tokens rescue 0
      @cost += @llm.record_cost(model: model, tokens_in: tokens_in, tokens_out: tokens_out)

      response.content
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

      chat = @llm.chat(model: model)
      response = chat.ask(prompt)

      tokens_in = response.input_tokens rescue 0
      tokens_out = response.output_tokens rescue 0
      @cost += @llm.record_cost(model: model, tokens_in: tokens_in, tokens_out: tokens_out)

      response.content
    rescue StandardError
      proposals.first[:proposal]
    end

    def over_budget?
      @cost >= MAX_COST
    end
  end
end
