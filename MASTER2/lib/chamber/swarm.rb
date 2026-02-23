# frozen_string_literal: true

module MASTER
  # Swarm - Generate many variations, curate best
  class Swarm
    SWARM_SIZE = 5

    def initialize(size: SWARM_SIZE)
      @size = size
    end

    def generate(prompt:, context: {})
      responses = []
      total_cost = 0

      # Fan out - get multiple responses using different approaches
      @size.times do |idx|
        tier = idx < 2 ? :strong : :fast # Mix of tiers for diversity

        begin
          result = LLM.ask(prompt, tier: tier)
          next unless result.ok?

          response = result.value
          cost = response.fetch(:cost, 0)
          total_cost += cost

          responses << {
            index: idx,
            model: response[:model],
            content: response[:content],
            tokens: (response.fetch(:tokens_in, 0)) + (response.fetch(:tokens_out, 0)),
          }
        rescue StandardError
          # Continue with other attempts
        end
      end

      return Result.err("No responses generated.") if responses.empty?

      # Curate - pick the best response
      best = curate(responses, prompt: prompt)
      total_cost += best[:curation_cost] || 0

      Result.ok({
                  responses: responses,
                  best: best[:selected],
                  reasoning: best[:reasoning],
                  cost: total_cost,
                })
    end

    private

    def curate(responses, prompt:)
      return { selected: responses.first, reasoning: "Only one response", curation_cost: 0 } if responses.size == 1

      curation_prompt = build_curation_prompt(responses, prompt)

      result = LLM.ask(curation_prompt, tier: :fast)
      return { selected: responses.first, reasoning: "Curation failed", curation_cost: 0 } unless result.ok?

      response = result.value
      cost = response.fetch(:cost, 0)

      # Parse selection
      content = response[:content].to_s
      selected_idx = begin
        content.match(/\[(\d+)\]/)[1].to_i
      rescue StandardError
        0
      end

      {
        selected: responses[selected_idx] || responses.first,
        reasoning: content,
        curation_cost: cost,
      }
    rescue StandardError => err
      { selected: responses.first, reasoning: "Curation failed: #{err.message}", curation_cost: 0 }
    end

    def build_curation_prompt(responses, original_prompt)
      options = responses.map.with_index do |r, idx|
        "response[#{idx}] (#{r[:model]})\n#{r[:content][0, 500]}"
      end.join("\n\n")

      <<~PROMPT
        Original request: #{original_prompt[0, 200]}

        #{options}

        Select the best response. Reply with [N] where N is the index, followed by a brief explanation.
      PROMPT
    end
  end
end
