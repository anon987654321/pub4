# frozen_string_literal: true

module MASTER
  class Council
    # Ideation methods - creative brainstorming cycle
    module Ideation
      # Creative mode: Brainstorm -> Critique -> Synthesize cycle
      def ideate(prompt:, constraints: [], cycles: 2)
        ideas = []
        critiques = []
        total_cost = 0

        cycles.times do
          brainstorm = generate_ideas(prompt, ideas, constraints)
          return brainstorm if brainstorm.err?
          ideas += brainstorm.value[:ideas]
          total_cost += brainstorm.value[:cost]

          critique = critique_ideas(ideas)
          return critique if critique.err?
          critiques << critique.value[:critique]
          total_cost += critique.value[:cost]
        end

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

      # Generate new ideas based on prompt and constraints
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
          parsed = content.scan(/^[\-\**]\s*(.+)/).flatten
          parsed = [content] if parsed.empty?
          Result.ok(ideas: parsed, cost: data[:cost] || 0)
        else
          Result.err("Brainstorm failed: #{result.error}")
        end
      end

      # Critique existing ideas to find weaknesses
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

      # Synthesize best elements from ideas and critiques
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
end
