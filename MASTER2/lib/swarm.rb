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
      @size.times do |i|
        tier = i < 2 ? :strong : :fast  # Mix of tiers for diversity
        
        begin
          result = LLM.ask(prompt, tier: tier)
          next unless result.ok?

          data = result.value
          cost = data[:cost] || 0
          total_cost += cost

          responses << {
            index: i,
            model: data[:model],
            content: data[:content],
            tokens: (data[:tokens_in] || 0) + (data[:tokens_out] || 0)
          }
        rescue StandardError => e
          # Continue with other attempts
        end
      end

      return Result.err("No responses generated") if responses.empty?

      # Curate - pick the best response
      best = curate(responses, prompt: prompt)
      total_cost += best[:curation_cost] || 0

      Result.ok({
        responses: responses,
        best: best[:selected],
        reasoning: best[:reasoning],
        cost: total_cost
      })
    end

    private

    def curate(responses, prompt:)
      return { selected: responses.first, reasoning: "Only one response", curation_cost: 0 } if responses.size == 1

      curation_prompt = build_curation_prompt(responses, prompt)
      
      result = LLM.ask(curation_prompt, tier: :fast)
      return { selected: responses.first, reasoning: "Curation failed", curation_cost: 0 } unless result.ok?

      data = result.value
      cost = data[:cost] || 0

      # Parse selection
      content = data[:content].to_s
      selected_idx = content.match(/\[(\d+)\]/)[1].to_i rescue 0

      {
        selected: responses[selected_idx] || responses.first,
        reasoning: content,
        curation_cost: cost
      }
    rescue StandardError => e
      { selected: responses.first, reasoning: "Curation failed: #{e.message}", curation_cost: 0 }
    end

    def build_curation_prompt(responses, original_prompt)
      options = responses.map.with_index do |r, i|
        "=== Response [#{i}] (#{r[:model]}) ===\n#{r[:content][0, 500]}"
      end.join("\n\n")

      <<~PROMPT
        Original request: #{original_prompt[0, 200]}

        #{options}

        Select the best response. Reply with [N] where N is the index, followed by a brief explanation.
      PROMPT
    end
  end
end
