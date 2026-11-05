# frozen_string_literal: true

require_relative "inter_model_contract"

module Master
  module Review
    module Council
      class Ideation
        DEFAULT_CYCLES = 2
        BUDGET_SECONDS = 4 * 60
        REQUIRED_CONSTRAINTS = %w[ROBUSTNESS SINGULARITY INTER_MODEL_CONTRACT].freeze

        def initialize(agent:, event_bus: nil, root: InterModelContract::REPO_ROOT)
          @agent = agent
          @bus = event_bus
          @root = File.expand_path(root)
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
          quota_result = fill_quota(prompt:, ideas:, critiques:, constraints:, deadline:)
          return quota_result if quota_result
          required = Master::Core::Proof::ALTERNATIVES_REQUIRED
          if ideas.uniq.size < required
            return Master::Result.err(
              "ideation: #{ideas.uniq.size} distinct approaches; #{required} required",
              category: :llm_failure
            )
          end

          synth_result = synthesize(prompt:, ideas:, critiques:, constraints:)
          return synth_result if synth_result.err?

          Master::Result.ok(ideas: ideas.uniq, critiques:, final: synth_result.value!)
        end

        private

        def fill_quota(prompt:, ideas:, critiques:, constraints:, deadline:)
          return if ideas.uniq.size >= Master::Core::Proof::ALTERNATIVES_REQUIRED || Time.now >= deadline

          more = brainstorm(prompt:, prior: ideas, constraints:)
          return more if more.err?

          additions = more.value!.uniq - ideas.uniq
          ideas.concat(additions)
          return if additions.empty?

          critique_result = critique(additions)
          return critique_result if critique_result.err?

          critiques << critique_result.value!
          nil
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

        def brainstorm(prompt:, prior:, constraints:)
          context = prior.any? ? "Prior ideas (avoid repeating): #{prior.join('; ')}\n\n" : ""
          constraint_prefix = constraints.any? ? "Constraints: #{constraints.join(', ')}\n\n" : ""
          minimum = [Master::Core::Proof::ALTERNATIVES_REQUIRED - prior.uniq.size, 1].max
          system_msg = "Generate at least #{minimum} distinct approaches. " \
                       "Return one structured finding per approach; put the complete approach in claim and use " \
                       "proposed_repair=none. Do not repeat a prior idea."
          model_prompt = <<~PROMPT
            #{constraint_prefix}#{context}Generate distinct approaches for: #{prompt}
            Return at least #{minimum} materially different candidates.
            With prior candidates, set position to mixed and explain that the new candidates are distinct.
          PROMPT
          prior_findings = idea_findings(prior)
          result = structured_exchange(
            model_prompt, role: "proposer", task: "Generate materially distinct approaches.",
            success_criteria: "Return at least #{minimum} distinct candidates in schema-valid findings.",
            constraints:, prior_findings:, system: system_msg
          )
          ideas = result.fetch("data").fetch("findings").filter_map do |finding|
            claim = finding.fetch("claim").strip
            claim unless claim.empty?
          end.uniq
          if ideas.empty?
            return Master::Result.err(
              "ideation: brainstorm returned no distinct candidates", category: :llm_failure
            )
          end

          Master::Result.ok(ideas)
        rescue StandardError => e
          report_error("brainstorm", e)
          Master::Result.err("ideation: brainstorm failed (#{e.class})", category: :llm_failure)
        end

        def critique(ideas)
          list = ideas.map { |idea| "- #{idea}" }.join("\n")
          system_msg = "Attack every candidate separately. Return exactly one finding for each supplied candidate. " \
                       "The finding claim must exactly repeat the candidate. Set proposed_repair to KEEP or " \
                       "REJECT: <specific reason>. Do not omit or invent candidates."
          model_prompt = <<~PROMPT
            Critique each candidate independently:
            #{list}

            For each candidate, identify the strongest argument that it is wrong, breaks existing behavior,
            or conflicts with an established decision. Preserve the exact candidate text in finding.claim.
            Use proposed_repair=KEEP or proposed_repair=REJECT: followed by a concrete reason.
            Return position mixed and evidence tied to the supplied candidates.
          PROMPT
          prior_findings = idea_findings(ideas)
          result = structured_exchange(
            model_prompt, role: "critic", task: "Adversarially assess each proposed approach.",
            success_criteria: "Exactly one schema-valid, explicit keep/reject verdict for every supplied candidate.",
            constraints: REQUIRED_CONSTRAINTS, prior_findings:, system: system_msg
          )
          findings = result.fetch("data").fetch("findings")
          claims = findings.map { |finding| finding.fetch("claim").strip }
          unless claims.size == ideas.size && claims.uniq.size == claims.size && claims.sort == ideas.sort
            return Master::Result.err(
              "ideation: critique did not cover the candidate set exactly", category: :llm_failure
            )
          end

          rendered = findings.map do |finding|
            verdict = finding.fetch("proposed_repair").strip
            unless verdict.match?(/\A(?:KEEP\b|REJECT\s*:)/i)
              return Master::Result.err(
                "ideation: critique omitted an explicit KEEP/REJECT verdict", category: :llm_failure
              )
            end

            "#{finding.fetch('claim')}\nVERDICT: #{verdict}"
          end
          Master::Result.ok(rendered.join("\n\n"))
        rescue StandardError => e
          report_error("critique", e)
          Master::Result.err("ideation: critique failed (#{e.class})", category: :llm_failure)
        end

        def synthesize(prompt:, ideas:, critiques:, constraints:)
          constraint_prefix = constraints.any? ? "Constraints: #{constraints.join(', ')}\n\n" : ""
          list = ideas.map { |idea| "- #{idea}" }.join("\n")
          crits = critiques.join("\n\n")
          system_msg = "Synthesize the best elements into one concrete, practical recommendation. " \
                       "Drop every candidate marked REJECT and retain only KEEP candidates. " \
                       "Put the recommendation in claim and the concrete next step in proposed_repair."
          model_prompt = <<~PROMPT
            Goal: #{prompt}
            #{constraint_prefix}
            Candidates:
            #{list}

            Critiques and explicit verdicts:
            #{crits}

            Return position mixed, cite the supplied goal and candidate/verdict set in position_evidence,
            and return exactly one finding for the final recommendation.
          PROMPT
          result = structured_exchange(
            model_prompt, role: "synthesizer", task: "Synthesize the strongest surviving approaches.",
            success_criteria: "One actionable recommendation grounded in the supplied candidates and verdicts.",
            constraints:, prior_findings: idea_findings(ideas), system: system_msg
          )
          findings = result.fetch("data").fetch("findings")
          if findings.size != 1
            return Master::Result.err(
              "ideation: synthesis must return exactly one recommendation", category: :llm_failure
            )
          end

          finding = findings.first
          final = [finding.fetch("claim").strip, finding.fetch("proposed_repair").strip]
            .reject { |part| part.empty? || part == "none" }.join("\n\n")
          if final.empty?
            return Master::Result.err(
              "ideation: synthesis returned an empty recommendation", category: :llm_failure
            )
          end

          Master::Result.ok(final)
        rescue StandardError => e
          report_error("synthesis", e)
          Master::Result.err("ideation: synthesis failed (#{e.class})", category: :llm_failure)
        end

        def structured_exchange(prompt, role:, task:, success_criteria:, constraints:, prior_findings:, system:)
          law_constraints = (Array(constraints).map(&:to_s) + REQUIRED_CONSTRAINTS).reject(&:empty?).uniq
          contract_prompt = InterModelContract.wrap_prompt(
            prompt,
            role:,
            task:,
            success_criteria:,
            constraints: law_constraints,
            artifact: prompt,
            prior_findings:
          )
          model = @agent.model if @agent.respond_to?(:model)
          InterModelContract.exchange(
            prompt: contract_prompt, role:, bus: @bus, root: @root, prior_findings:, model:
          ) do |outbound, _retrying|
            @agent.ask_once(outbound, system:)
          end
        end

        def idea_findings(ideas)
          Array(ideas).each_with_index.map do |idea, index|
            {
              "severity" => "info",
              "location" => "candidate #{index + 1}",
              "evidence" => "Candidate supplied by the preceding ideation stage.",
              "claim" => idea.to_s,
              "proposed_repair" => "none"
            }
          end
        end

        def report_error(stage, error)
          @bus&.publish("ideation:error", stage:, error_class: error.class.name)
        end
      end
    end
  end
end
