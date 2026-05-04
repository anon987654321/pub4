# frozen_string_literal: true

module Master
  module Council
    class Ideation
      DEFAULT_CYCLES = 2

      def initialize(agent:, event_bus: nil)
        @agent = agent
        @bus   = event_bus
      end

      def ideate(prompt, constraints: [], cycles: DEFAULT_CYCLES)
        ideas     = []
        critiques = []

        cycles.times do |cycle|
          result = brainstorm(prompt, ideas, constraints)
          return result if result.err?
          ideas += result.value
          @bus&.publish("ideation:cycle", cycle: cycle + 1, ideas: ideas.size)

          result = critique(ideas)
          return result if result.err?
          critiques << result.value
        end

        result = synthesize(prompt:, ideas:, critiques:, constraints:)
        return result if result.err?

        Master::Result.ok(ideas: ideas, critiques: critiques, final: result.value)
      end

      private

      def brainstorm(prompt, prior, constraints)
        context           = prior.any? ? "Prior ideas (avoid repeating): #{prior.join('; ')}\n\n" : ""
        constraint_prefix = constraints.any? ? "Constraints: #{constraints.join(', ')}\n\n" : ""
        raw     = @agent.ask_once(<<~PROMPT, system: "Generate 3-5 novel, bold ideas. One idea per bullet (- prefix).")
          #{constraint_prefix}#{context}Generate ideas for: #{prompt}
        PROMPT
        return Master::Result.err("ideation: brainstorm failed") if raw.to_s.strip.empty?

        parsed = raw.scan(/^[-*]\s*(.+)/).flatten
        parsed = [raw.strip] if parsed.empty?
        Master::Result.ok(parsed)
      end

      def critique(ideas)
        list = ideas.map { |idea| "- #{idea}" }.join("\n")
        raw  = @agent.ask_once(<<~PROMPT, system: "Critique these ideas. Identify weaknesses, blind spots, risks. Be direct.")
          #{list}
        PROMPT
        return Master::Result.err("ideation: critique failed") if raw.to_s.strip.empty?

        Master::Result.ok(raw.strip)
      end

      def synthesize(prompt:, ideas:, critiques:, constraints:)
        constraint_prefix = constraints.any? ? "Constraints: #{constraints.join(', ')}\n\n" : ""
        list              = ideas.map { |idea| "- #{idea}" }.join("\n")
        crits = critiques.join("\n---\n")
        raw   = @agent.ask_once(<<~PROMPT, system: "Synthesize the best elements into a concrete, practical recommendation. Preserve innovation. Address valid critiques.")
          Goal: #{prompt}
          #{constraint_prefix}
          Ideas:
          #{list}

          Critiques:
          #{crits}
        PROMPT
        return Master::Result.err("ideation: synthesis failed") if raw.to_s.strip.empty?

        Master::Result.ok(raw.strip)
      end
    end
  end
end
