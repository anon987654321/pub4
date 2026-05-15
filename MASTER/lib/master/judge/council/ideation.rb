# frozen_string_literal: true

module Master
  module Judge
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
          brainstorm_result = brainstorm(prompt, ideas, constraints)
          return brainstorm_result if brainstorm_result.err?
          ideas += brainstorm_result.value
          @bus&.publish("ideation:cycle", cycle: cycle + 1, ideas: ideas.size)

          critique_result = critique(ideas)
          return critique_result if critique_result.err?
          critiques << critique_result.value
        end

        synth_result = synthesize(prompt:, ideas:, critiques:, constraints:)
        return synth_result if synth_result.err?

        Master::Result.ok(ideas: ideas, critiques: critiques, final: synth_result.value)
      end

      private

      def brainstorm(prompt, prior, constraints)
        context           = prior.any? ? "Prior ideas (avoid repeating): #{prior.join('; ')}\n\n" : ""
        constraint_prefix = constraints.any? ? "Constraints: #{constraints.join(', ')}\n\n" : ""
        system_msg = "Generate 3-5 novel, bold ideas. One idea per bullet (- prefix)."
        raw = @agent.ask_once(<<~PROMPT, system: system_msg)
          #{constraint_prefix}#{context}Generate ideas for: #{prompt}
        PROMPT
        raw_text = raw.to_s
        return Master::Result.err("ideation: brainstorm failed") if raw_text.strip.empty?

        parsed = raw_text.scan(/^[-*]\s*(.+)/).flatten
        parsed = [raw_text.strip] if parsed.empty?
        Master::Result.ok(parsed)
      end

      def critique(ideas)
        list       = ideas.map { |idea| "- #{idea}" }.join("\n")
        system_msg = "Critique these ideas. Identify weaknesses, blind spots, risks. Be direct."
        raw        = @agent.ask_once(<<~PROMPT, system: system_msg)
          #{list}
        PROMPT
        raw_text = raw.to_s
        return Master::Result.err("ideation: critique failed") if raw_text.strip.empty?

        Master::Result.ok(raw_text.strip)
      end

      def synthesize(prompt:, ideas:, critiques:, constraints:)
        constraint_prefix = constraints.any? ? "Constraints: #{constraints.join(', ')}\n\n" : ""
        list              = ideas.map { |idea| "- #{idea}" }.join("\n")
        crits      = critiques.join("\n\n")
        system_msg = "Synthesize the best elements into a concrete, practical recommendation. " \
                     "Preserve innovation. Address valid critiques."
        raw = @agent.ask_once(<<~PROMPT, system: system_msg)
          Goal: #{prompt}
          #{constraint_prefix}
          Ideas:
          #{list}

          Critiques:
          #{crits}
        PROMPT
        raw_text = raw.to_s
        return Master::Result.err("ideation: synthesis failed") if raw_text.strip.empty?

        Master::Result.ok(raw_text.strip)
      end
    end
  end
  end
end
