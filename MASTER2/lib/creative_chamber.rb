# frozen_string_literal: true

module MASTER
  # CreativeChamber - Creative ideation with brainstorm/critique cycles
  class CreativeChamber
    MODELS = {
      visionary:  "deepseek/deepseek-v3",    # Wild ideas
      critic:     "openai/gpt-4.1-mini",     # Reality check
      synthesizer: "deepseek/deepseek-r1"    # Combine best
    }.freeze

    def initialize(cycles: 2)
      @cycles = cycles
    end

    def ideate(prompt:, constraints: [])
      ideas = []
      critiques = []
      total_cost = 0

      @cycles.times do |cycle|
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
      synthesis = synthesize(prompt, ideas, critiques, constraints)
      return synthesis if synthesis.err?
      total_cost += synthesis.value[:cost]

      Result.ok({
        ideas: ideas,
        critiques: critiques,
        final: synthesis.value[:synthesis],
        cost: total_cost
      })
    end

    private

    def generate_ideas(prompt, existing_ideas, constraints)
      system_prompt = <<~SYS
        You are a creative visionary. Generate 3-5 novel ideas.
        Be bold, unconventional, surprising.
        Constraints to respect: #{constraints.join(', ')}
        #{"Previous ideas (don't repeat): #{existing_ideas.join(', ')}" if existing_ideas.any?}
      SYS

      model = MODELS[:visionary]
      begin
        chat = LLM.chat(model: model)
        response = chat.ask("#{system_prompt}\n\nGenerate ideas for: #{prompt}")

        cost = LLM.record_cost(
          model: model,
          tokens_in: response.input_tokens || 200,
          tokens_out: response.output_tokens || 300
        )

        # Parse bullet points as ideas
        ideas = response.content.scan(/^[\-\*•]\s*(.+)/).flatten
        ideas = [response.content] if ideas.empty?

        Result.ok({ ideas: ideas, cost: cost })
      rescue => e
        LLM.trip!(model)
        Result.err("Brainstorm failed: #{e.message}")
      end
    end

    def critique_ideas(ideas)
      prompt = <<~PROMPT
        Critique these ideas honestly. What are the weaknesses, blind spots, implementation challenges?

        Ideas:
        #{ideas.map { |i| "- #{i}" }.join("\n")}
      PROMPT

      model = MODELS[:critic]
      begin
        chat = LLM.chat(model: model)
        response = chat.ask(prompt)

        cost = LLM.record_cost(
          model: model,
          tokens_in: response.input_tokens || 200,
          tokens_out: response.output_tokens || 300
        )

        Result.ok({ critique: response.content, cost: cost })
      rescue => e
        LLM.trip!(model)
        Result.err("Critique failed: #{e.message}")
      end
    end

    def synthesize(original_prompt, ideas, critiques, constraints)
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

      model = MODELS[:synthesizer]
      begin
        chat = LLM.chat(model: model)
        response = chat.ask(prompt)

        cost = LLM.record_cost(
          model: model,
          tokens_in: response.input_tokens || 400,
          tokens_out: response.output_tokens || 500
        )

        Result.ok({ synthesis: response.content, cost: cost })
      rescue => e
        LLM.trip!(model)
        Result.err("Synthesis failed: #{e.message}")
      end
    end
  end
end
