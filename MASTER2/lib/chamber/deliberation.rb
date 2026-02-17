# frozen_string_literal: true

module MASTER
  class Council
    # Deliberation methods - proposal generation and arbiter decisions
    module Deliberation
      # Main deliberation flow - gather proposals and reach consensus
      def deliberate(code, filename: "code", participants: %i[sonnet deepseek])
        @proposals = []
        @rounds = 0

        participants.each do |model_key|
          break if over_budget?

          model = MODELS[model_key] || LLM.select_model
          next unless model && @llm.circuit_closed?(model)

          proposal = propose(code, model, filename)
          @proposals << { model: model_key, proposal: proposal } if proposal
        end

        return Result.err("No proposals generated.") if @proposals.empty?

        council_result = multi_round_review(code, @proposals.first[:proposal])

        arbiter_model = MODELS[ARBITER] || LLM.select_model
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

      private

      # Generate a proposal for code improvement
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
      rescue StandardError => e
        @llm.open_circuit!(model)
        nil
      end

      # Arbiter makes final decision from multiple proposals
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
      rescue StandardError => e
        proposals.first[:proposal]
      end
    end
  end
end
