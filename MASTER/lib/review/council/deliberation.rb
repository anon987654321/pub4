# frozen_string_literal: true

require_relative "quality_framework"

module Master
  module Review
    module Council
      class Deliberation
        include DeliberationSynthesis
        include DeliberationPromptBuilder

        MAX_CONCURRENT = 4
        MAX_CODE_BYTES = 8_192
        TRUNCATE_MARKER = "\n... [truncated to #{MAX_CODE_BYTES} bytes for review]".freeze
        TOTAL_BUDGET_S = 120
        MIN_QUORUM = 3
        CONVERGENCE_ROUNDS = 3
        CONVERGENCE_OVERLAP = 0.7
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

        def review(code, context: nil, personas: nil)
          active = active_personas(personas)
          return Result.err("council: no personas configured", category: :validation) if active.empty?

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
          Result.err("council: quorum not reached (#{feedback.size}/#{@personas.size})", category: :timeout)
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
            break feedback if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline || circuit_open?

            turn_context = feedback.empty? ? context : "#{context}\n\nprior turns:\n#{format_prior_turns(feedback)}"
            entry = ask_persona(persona:, code:, context: turn_context)
            feedback << entry if entry
          end
        end

        def circuit_open?
          breaker = @agent.respond_to?(:circuit_breaker) ? @agent.circuit_breaker : nil
          breaker.respond_to?(:open_models) && !breaker.open_models.empty?
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "deliberation.circuit_open", event_bus: @bus)
          false
        end

        def ask_persona(persona:, code:, context:)
          model = persona.respond_to?(:model) ? persona.model : nil
          prompt = build_prompt(persona:, code:, context:)
          response = model ? @agent.ask_once(prompt, model:) : @agent.ask(prompt)
          entry = persona_entry(persona, response, model)
          @bus&.publish(:council_feedback, entry)
          entry
        rescue StandardError => e
          @bus&.publish("council:persona_error", persona: persona.name, error: e.message)
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
