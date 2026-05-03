# frozen_string_literal: true

module Master
  module Council
    class Ideation
      Result = Master::Result

      DEFAULT_CYCLES = 2

      def initialize(agent:, event_bus: nil)
        @agent = agent
        @bus   = event_bus
      end

      def ideate(prompt, constraints: [], cycles: DEFAULT_CYCLES)
        ideas     = []
        critiques = []

        cycles.times do |i|
          r = brainstorm(prompt, ideas, constraints)
          return r if r.err?
          ideas += r.value
          @bus&.publish("ideation:cycle", cycle: i + 1, ideas: ideas.size)

          r = critique(ideas)
          return r if r.err?
          critiques << r.value
        end

        r = synthesize(prompt, ideas, critiques, constraints)
        return r if r.err?

        Result.ok(ideas: ideas, critiques: critiques, final: r.value)
      end

      private

      def brainstorm(prompt, prior, constraints)
        context = prior.any? ? "Prior ideas (avoid repeating): #{prior.join('; ')}\n\n" : ""
        c       = constraints.any? ? "Constraints: #{constraints.join(', ')}\n\n" : ""
        raw     = @agent.ask_once(<<~PROMPT, system: "Generate 3-5 novel, bold ideas. One idea per bullet (- prefix).")
          #{c}#{context}Generate ideas for: #{prompt}
        PROMPT
        return Result.err("ideation: brainstorm failed") if raw.to_s.strip.empty?

        parsed = raw.scan(/^[-*]\s*(.+)/).flatten
        parsed = [raw.strip] if parsed.empty?
        Result.ok(parsed)
      end

      def critique(ideas)
        list = ideas.map { |i| "- #{i}" }.join("\n")
        raw  = @agent.ask_once(<<~PROMPT, system: "Critique these ideas. Identify weaknesses, blind spots, risks. Be direct.")
          #{list}
        PROMPT
        return Result.err("ideation: critique failed") if raw.to_s.strip.empty?

        Result.ok(raw.strip)
      end

      def synthesize(prompt, ideas, critiques, constraints)
        c     = constraints.any? ? "Constraints: #{constraints.join(', ')}\n\n" : ""
        list  = ideas.map { |i| "- #{i}" }.join("\n")
        crits = critiques.join("\n---\n")
        raw   = @agent.ask_once(<<~PROMPT, system: "Synthesize the best elements into a concrete, practical recommendation. Preserve innovation. Address valid critiques.")
          Goal: #{prompt}
          #{c}
          Ideas:
          #{list}

          Critiques:
          #{crits}
        PROMPT
        return Result.err("ideation: synthesis failed") if raw.to_s.strip.empty?

        Result.ok(raw.strip)
      end
    end
  end
end
