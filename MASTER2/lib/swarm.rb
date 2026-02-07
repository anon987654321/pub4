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

      # Fan out - get multiple responses from different models or temperatures
      @size.times do |i|
        model_info = LLM.select_model(prompt.length)
        next unless model_info

        begin
          chat = LLM.chat(model: model_info[:model])
          response = chat.ask(prompt)

          tokens_in = response.input_tokens || 100
          tokens_out = response.output_tokens || 200
          cost = LLM.record_cost(model: model_info[:model], tokens_in: tokens_in, tokens_out: tokens_out)
          total_cost += cost

          responses << {
            index: i,
            model: model_info[:model],
            content: response.content,
            tokens: tokens_in + tokens_out
          }
        rescue => e
          LLM.trip!(model_info[:model])
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
      model_info = LLM.select_model(curation_prompt.length)
      return { selected: responses.first, reasoning: "No model available", curation_cost: 0 } unless model_info

      begin
        chat = LLM.chat(model: model_info[:model])
        response = chat.ask(curation_prompt)

        cost = LLM.record_cost(
          model: model_info[:model],
          tokens_in: response.input_tokens || 200,
          tokens_out: response.output_tokens || 100
        )

        # Parse selection
        content = response.content
        selected_idx = content.match(/\[(\d+)\]/)[1].to_i rescue 0

        {
          selected: responses[selected_idx] || responses.first,
          reasoning: content,
          curation_cost: cost
        }
      rescue => e
        { selected: responses.first, reasoning: "Curation failed: #{e.message}", curation_cost: 0 }
      end
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
