# frozen_string_literal: true

module Master
  module Review
    module Council
      class Ideation
        DEFAULT_CYCLES = 2
        BUDGET_SECONDS = 4 * 60

        def initialize(agent:, event_bus: nil)
          @agent = agent
          @bus = event_bus
        end

        def ideate(prompt, constraints: [], cycles: DEFAULT_CYCLES, budget_seconds: BUDGET_SECONDS)
          ideas = []
          critiques = []
          deadline = Time.now + budget_seconds

          cycles.times do |cycle|
            err = run_ideation_cycle(cycle, prompt:, ideas:, critiques:, constraints:, deadline:)
            return err if err
          end

          return Master::Result.err("ideation: budget expired", category: :timeout) if Time.now >= deadline
          fill_quota(prompt:, ideas:, constraints:, deadline:)
          synth_result = synthesize(prompt:, ideas:, critiques:, constraints:)
          return synth_result if synth_result.err?

          Master::Result.ok(ideas: ideas.uniq, critiques:, final: synth_result.value!)
        end

        private

        def fill_quota(prompt:, ideas:, constraints:, deadline:)
          return if ideas.uniq.size >= Master::Core::Proof::ALTERNATIVES_REQUIRED || Time.now >= deadline

          more = brainstorm(prompt:, prior: ideas, constraints:)
          ideas.concat(more.value!) if more.ok?
        end

        def run_ideation_cycle(cycle, prompt:, ideas:, critiques:, constraints:, deadline:)
          return Master::Result.err("ideation: budget expired", category: :timeout) if Time.now >= deadline
          brainstorm_result = brainstorm(prompt:, prior: ideas, constraints:)
          return brainstorm_result if brainstorm_result.err?
          ideas.concat(brainstorm_result.value!)
          @bus&.publish("ideation:cycle", cycle: cycle + 1, ideas: ideas.size)

          return Master::Result.err("ideation: budget expired", category: :timeout) if Time.now >= deadline
          critique_result = critique(ideas)
          return critique_result if critique_result.err?
          critiques << critique_result.value!

          nil
        end

        def circuit_open?
          breaker = @agent.respond_to?(:circuit_breaker) ? @agent.circuit_breaker : nil
          false unless breaker.respond_to?(:open_models)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Ideation.circuit_open?")
          false
        end

        def brainstorm(prompt:, prior:, constraints:)
          context = prior.any? ? "Prior ideas (avoid repeating): #{prior.join('; ')}\n\n" : ""
          constraint_prefix = constraints.any? ? "Constraints: #{constraints.join(', ')}\n\n" : ""
          system_msg = "Generate at least 8 distinct approaches. One idea per bullet (- prefix)."
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
          list = ideas.map { |idea| "- #{idea}" }.join("\n")
          # Adversarial, per proposal, with a verdict — a critique that only
          # muses about the pool eliminates nothing, and the synthesis then
          # keeps everything. Each proposal gets attacked and either survives
          # or is rejected by name.
          system_msg = "Attack each idea separately: state the strongest argument that it is wrong, " \
                       "breaks existing behavior, or fights a decision already made. " \
                       "End each with 'VERDICT: keep' or 'VERDICT: reject — <reason>'. Be direct."
          raw = @agent.ask_once(<<~PROMPT, system: system_msg)
          #{list}
        PROMPT
          raw_text = raw.to_s
          return Master::Result.err("ideation: critique failed") if raw_text.strip.empty?

          Master::Result.ok(raw_text.strip)
        end

        def synthesize(prompt:, ideas:, critiques:, constraints:)
          constraint_prefix = constraints.any? ? "Constraints: #{constraints.join(', ')}\n\n" : ""
          list = ideas.map { |idea| "- #{idea}" }.join("\n")
          crits = critiques.join("\n\n")
          system_msg = "Synthesize the best elements into a concrete, practical recommendation. " \
                       "Drop every idea the critiques rejected; keep only survivors and say which. " \
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
