# frozen_string_literal: true

require_relative "quality_framework"

module Master
  module Review
    module Council
      class Deliberation
        include DeliberationSynthesis
        include DeliberationPromptBuilder

        attr_reader :agent, :bus

        # Kept at 4 deliberately. collect_parallel runs personas in slices of
        # this size, so halving it doubles the number of batches: measured
        # 2026-07-31, four concurrent calls take ~203s each and two take ~118s,
        # which over 26 personas is 7 x 203 = 1421s against 13 x 118 = 1534s.
        # Lower concurrency buys per-call margin and spends more total wall
        # clock, which is the opposite of what it looks like it does.
        MAX_CONCURRENT = 4
        MAX_CODE_BYTES = 8_192
        TRUNCATE_MARKER = "\n... [truncated to #{MAX_CODE_BYTES} bytes for review]".freeze
        # One deadline for the WHOLE council, not per persona or per batch —
        # see collect_parallel, which computes it once and hands the same
        # instant to every join_or_kill.
        #
        # At 120s this made most of the council structurally unreachable. A
        # single persona answering a real critique prompt took 114-134s on this
        # machine, so the first batch of four consumed the entire budget and
        # batches two through seven were killed the moment they were joined.
        # MIN_QUORUM = 3 is the only reason it ever returned a verdict: the
        # 2026-07-31 critique that "passed" was three voices out of twenty-six,
        # which is exactly the three it printed.
        #
        # 600s covers roughly three batches, so around twelve personas answer
        # instead of three. Hearing all twenty-six needs ~1421s, which is a
        # legitimate choice and a 24-minute critique per subsystem — three of
        # them in a full gate. The arithmetic is written down so that is an
        # informed one-line change rather than a guess.
        TOTAL_BUDGET_S = 600
        MIN_QUORUM = 3
        CONVERGENCE_ROUNDS = 3
        # How much of the council must agree before a round counts as converged.
        # The same number lived twice: here as a literal, and in council.yml as
        # `parameters.consensus_threshold`, which nothing read. Two copies of one
        # constant is the shape SINGULARITY forbids, and the unread one was the
        # one the requirements register names. It is the source now; the literal
        # is the fallback for a council.yml that cannot be read at all.
        # load_yaml already answers {} for a missing or unparseable file, so the
        # literal below is the fallback and no rescue is needed to reach it.
        council_params = Master.load_yaml(Master::COUNCIL_PATH, default: {})["parameters"]
        CONVERGENCE_OVERLAP = Float(council_params.to_h["consensus_threshold"] || 0.7)
        CONVERGENCE_TEXT_SIM = 0.6
        LEGACY_PROMPTS_PATH = Master.data_path("prompts", "council.yml").freeze

        def self.questions = @questions ||= QualityFramework.questions

        def self.sample_question(persona)
          lens = persona.respond_to?(:cognitive_lens) ? persona.cognitive_lens : nil
          questions[lens.to_s]&.sample if lens
        end

        def self.quality_brief(domain = :general) = QualityFramework.brief(domain)

        def self.prompts
          @prompts ||= begin
            council = Master.load_yaml(Master::COUNCIL_PATH) || {}
            configured = council["prompts"]
            configured.is_a?(Hash) && !configured.empty? ? configured : Master.load_yaml(LEGACY_PROMPTS_PATH)
          end
        end

        def initialize(personas:, agent:, event_bus: nil, axioms: nil, **options)
          @personas = personas
          @agent = agent
          @bus = event_bus
          @rules = axioms
          @judge_enabled = options.fetch(:judge_enabled, true)
          @mode = options.fetch(:mode, :parallel)
          @persona_failures = []
          @persona_failures_lock = Mutex.new
          validate_dependencies!
        end

        def review_convergent(code, context: nil, max_rounds: CONVERGENCE_ROUNDS)
          history = []
          round_context = context
          max_rounds.times do |index|
            result = review_round(code, round_context, index + 1, max_rounds)
            return result if result.err?

            history << result.value!
            if history.size >= 2 && converged?(history[-2], history[-1])
              @bus&.publish(:council_converged, round: index + 1)
              break
            end

            round_context = feedback_summary(history.last, context)
          end
          Result.ok(Array(history.last))
        end

        # The key check is one layer down, in LLMDispatcher#send_with_cache,
        # because ideation and the semantic rules reach a model without passing
        # through here. This one still refuses early rather than spending
        # TOTAL_BUDGET_S discovering it per persona.
        def review(code, context: nil, personas: nil)
          active = active_personas(personas)
          return Result.err("council: no personas, or no provider key", category: :validation) if active.empty? || !Master.any_api_key_present?

          context = reflexion_context(context)
          feedback = collect_feedback(active, code, context)
          quorum = quorum_error(feedback)
          return quorum if quorum

          veto = enforce_veto(feedback)
          return veto if veto

          append_judge_synthesis(feedback:, code:, context:)
          publish_confidence(feedback)
          Result.ok(feedback)
        rescue StandardError => e
          Result.err("council: #{e.message}", category: :unknown)
        end

        private

        def review_round(code, context, round, maximum)
          @bus&.publish(:council_round_start, round:, max: maximum)
          @bus&.publish(:engineering_fit, fit: classify_engineering_fit(code))
          review(code, context:)
        end

        def active_personas(names)
          active = names ? @personas.select { |persona| names.include?(persona.name) } : @personas
          active.empty? && !@personas.empty? ? @personas : active
        end

        def reflexion_context(context)
          return context unless @bus

          root = @rules&.instance_variable_get(:@root) || Dir.pwd
          recent = Trace::ReflexionLedger.new(event_bus: @bus, root:).recent(3)
          return context if recent.empty?

          [context, "Recent reflexions for rule adherence: #{recent.join(' | ')}"].compact.join("\n")
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "deliberation.reflexion", event_bus: @bus)
          context
        end

        def collect_feedback(personas, code, context)
          method = @mode == :sequential ? :collect_sequential : :collect_parallel
          send(method, code:, context:, personas:)
        end

        def quorum_error(feedback)
          quorum = [MIN_QUORUM, @personas.size].min
          return if feedback.size >= quorum

          @bus&.publish(:council_timeout, completed: feedback.size, total: @personas.size)
          # The tally, not just the score. "quorum not reached (2/26)" sent an
          # operator into the per-persona log lines to learn that the answer
          # was "OpenRouter is out of credits" — the reasons were already
          # collected one layer down, and the error is where they get read.
          Result.err(
            "council: quorum not reached (#{feedback.size}/#{@personas.size})#{failure_summary}",
            category: :timeout,
          )
        end

        def failure_summary
          tally = @persona_failures_lock.synchronize { @persona_failures.tally }
          return "" if tally.empty?

          " — #{tally.sort_by { |_, count| -count }.map { |reason, count| "#{count}x #{reason}" }.join(", ")}"
        end

        # A stable slug per failure class, so 24 stack-trace variants tally as
        # three reasons an operator can act on.
        def failure_reason(message)
          case message
          when /insufficient credits/i then "insufficient_credits"
          when /not wired to any LLM/i then "no_provider_reached"
          when /claude-cli/i then "claude_cli_error"
          when /timed out|timeout/i then "timeout"
          when /rate.?limit/i then "rate_limited"
          else "error"
          end
        end

        def classify_engineering_fit(code)
          bytes = code.to_s.bytesize
          verdict = if bytes < 256
                      :under
                    elsif bytes > 500_000
                      :over
                    else
                      :fit
                    end
          config = Master.load_yaml(Master::RULES_PATH).fetch("engineering_fit", {})
          {
            verdict:,
            load: "artifact ~#{bytes} bytes across ~#{code.to_s.lines.size} lines",
            why: config["why_required"] || "load drives the verdict",
          }
        end

        def collect_parallel(code:, context:, personas: @personas)
          return [] if circuit_open?

          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + TOTAL_BUDGET_S
          personas.each_slice(MAX_CONCURRENT).flat_map do |batch|
            threads = batch.map do |persona|
              Thread.new { ask_persona(persona:, code:, context:) }
            end
            threads.filter_map { |thread| join_or_kill(thread, deadline) }
          end
        end

        def collect_sequential(code:, context:, personas: @personas)
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + TOTAL_BUDGET_S
          personas.each_with_object([]) do |persona, feedback|
            break feedback if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline || circuit_open?(persona)

            turn_context = feedback.empty? ? context : "#{context}\n\nprior turns:\n#{format_prior_turns(feedback)}"
            entry = ask_persona(persona:, code:, context: turn_context)
            feedback << entry if entry
          end
        end

        # Only genuinely blocked if every model this call could fall back to
        # has an open breaker. A persona with its own fixed model override
        # has no fallback of its own; a persona without one shares the
        # agent's full fallback chain -- an unrelated model at the front of
        # that chain being down must not abort deliberation for every
        # persona when a healthy fallback further down is still usable.
        def circuit_open?(persona = nil)
          breaker = @agent.respond_to?(:circuit_breaker) ? @agent.circuit_breaker : nil
          return false unless breaker
          return false unless breaker.respond_to?(:open?)

          models = candidate_models_for(persona)
          return false if models.empty?

          models.all? { |m| breaker.open?(m) }
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "deliberation.circuit_open", event_bus: @bus)
          false
        end

        def candidate_models_for(persona)
          override = persona&.respond_to?(:model) ? persona.model : nil
          return [override] if override
          return Array(@agent.candidate_models) if @agent.respond_to?(:candidate_models)

          @agent.respond_to?(:model) ? Array(@agent.model) : []
        end

        def ask_persona(persona:, code:, context:)
          model = persona.respond_to?(:model) ? persona.model : nil
          temperature = persona.respond_to?(:temperature) ? persona.temperature : nil
          prompt = build_prompt(persona:, code:, context:)
          response = if model
                       @agent.ask_once(prompt, model:, temperature:)
                     else
                       @agent.ask(prompt, temperature:)
                     end
          entry = persona_entry(persona, response, model)
          @bus&.publish(:council_feedback, entry)
          entry
        rescue StandardError => e
          @bus&.publish("council:persona_error", persona: persona.name, error: e.message)
          Master::Trace::Dmesg.status("council0", "persona_error persona=#{persona.name} #{e.class}: #{e.message}")
          @persona_failures_lock.synchronize { @persona_failures << failure_reason(e.message) }
          nil
        end

        def persona_entry(persona, response, model)
          {
            persona: persona.name, role: persona.role, veto_role: veto_role?(persona),
            axiom: primary_axiom(persona), model:, feedback: response,
            confidence: score_confidence(response)
          }
        end

        def format_prior_turns(entries)
          lines = entries.map do |entry|
            "#{entry[:persona]} (#{entry[:role]}): #{entry[:feedback].to_s.lines.first(3).join.strip}"
          end
          lines.join("\n\n")
        end

        def join_or_kill(thread, deadline)
          remaining = [deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC), 0.1].max
          return thread.value if thread.join(remaining)

          thread.kill
          nil
        end

        def validate_dependencies!
          raise ArgumentError, "personas must be an array" unless @personas.is_a?(Array)
          raise ArgumentError, "agent must respond to :ask" unless @agent.respond_to?(:ask)
        end
      end
    end
  end
end
