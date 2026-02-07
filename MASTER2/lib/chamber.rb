# frozen_string_literal: true

module MASTER
  # Chamber - Multi-model deliberation for code refinement
  class Chamber
    MODELS = {
      sonnet: "anthropic/claude-sonnet-4",
      deepseek: "deepseek/deepseek-r1",
      gpt: "openai/gpt-4.1-mini",
    }.freeze

    ARBITER = :sonnet
    MAX_ROUNDS = 3
    MAX_COST = 0.50
    CONSENSUS_THRESHOLD = 0.6

    attr_reader :cost, :rounds, :proposals

    def initialize(llm: LLM)
      @llm = llm
      @cost = 0.0
      @rounds = 0
      @proposals = []
    end

    def deliberate(code, filename: "code", participants: %i[sonnet deepseek])
      @proposals = []
      @rounds = 0

      participants.each do |model_key|
        break if over_budget?

        model = MODELS[model_key]
        next unless model && @llm.healthy?(model)

        proposal = get_proposal(code, model, filename)
        @proposals << { model: model_key, proposal: proposal } if proposal
      end

      return Result.err("No proposals generated") if @proposals.empty?

      arbiter_model = MODELS[ARBITER]
      if @llm.healthy?(arbiter_model)
        final = arbiter_decision(code, @proposals, arbiter_model)
        Result.ok(
          original: code,
          proposals: @proposals,
          final: final,
          cost: @cost,
          rounds: @rounds,
        )
      else
        Result.ok(
          original: code,
          proposals: @proposals,
          final: @proposals.first[:proposal],
          cost: @cost,
          rounds: @rounds,
        )
      end
    end

    private

    def get_proposal(code, model, filename)
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
      @llm.trip!(model)
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
