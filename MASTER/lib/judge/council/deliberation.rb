# frozen_string_literal: true

require_relative "quality_framework"

module Master
  module Judge
    module Council
      class Deliberation
        MAX_CONCURRENT = 4
        MAX_CODE_BYTES = 8_192
        TRUNCATE_MARKER = "\n... [truncated to #{MAX_CODE_BYTES} bytes for review]".freeze
        JUDGE_TIMEOUT = 30
        TOTAL_BUDGET_S = 120
        MIN_QUORUM = 3
        CONVERGENCE_ROUNDS = 3
        CONVERGENCE_OVERLAP = 0.7
        CONVERGENCE_TEXT_SIM = 0.6

        @questions = nil

        def self.questions
          @questions ||= QualityFramework.questions
        end

        def self.sample_question(persona)
          lens = persona.respond_to?(:cognitive_lens) ? persona.cognitive_lens : nil
          return nil unless lens
          questions[lens.to_s]&.sample
        end

        def self.quality_brief(domain = :general)
          QualityFramework.brief(domain)
        end

        def initialize(personas:, agent:, event_bus: nil, axioms: nil, judge_enabled: true, mode: :parallel)
          @personas = personas
          @agent = agent
          @bus = event_bus
          @rules = axioms
          @judge_enabled = judge_enabled
          @mode = mode
          validate_dependencies!
        end

        def review_convergent(code, context: nil, max_rounds: CONVERGENCE_ROUNDS)
          history = []
          round_context = context
          max_rounds.times do |i|
            @bus&.publish(:council_round_start, round: i + 1, max: max_rounds)
            # Classify engineering_fit per rules.yml; respect laws priority + inverted pyramid
            fit = classify_engineering_fit(code)
            @bus&.publish(:engineering_fit, fit: fit)
            review_result = review(code, context: round_context)
            return review_result unless review_result.is_a?(Master::Result::Ok)
            feedback = review_result.value!
            history << feedback
            if history.size >= 2 && converged?(history[-2], history[-1])
              @bus&.publish(:council_converged, round: i + 1)
              break
            end
            round_context = feedback_summary(feedback, context)
          end
          Master::Result.ok(Array(history.last))
        end

        def review(code, context: nil, personas: nil)
          active = personas ? @personas.select { |p| personas.include?(p.name) } : @personas
          active = @personas if active.empty?
          # Inject ReflexionLedger recent for strict self-correction on rule violations (rules.yml)
          if @bus
            begin
              reflex = Trace::ReflexionLedger.new(event_bus: @bus, root: (@rules&.root || Dir.pwd)).recent(3)
              context = [context, "Recent reflexions for rule adherence: #{reflex.join(' | ')}"].compact.join("\n") if reflex.any?
            rescue StandardError => e
              Master::Ground::Swallow.log(e, context: "deliberation.reflexion")
            end
          end
          return Master::Result.err("council: no personas configured", category: :validation) if active.empty?

          feedback = @mode == :sequential ? collect_sequential(code:, context:, personas: active) : collect_parallel(code:, context:, personas: active)
          effective_quorum = [MIN_QUORUM, @personas.size].min
          if feedback.size < effective_quorum
            @bus&.publish(:council_timeout, completed: feedback.size, total: @personas.size)
            quorum_msg = "council: quorum not reached (#{feedback.size}/#{@personas.size})"
            return Master::Result.err(quorum_msg, category: :timeout)
          end

          veto_result = enforce_veto(feedback)
          return veto_result if veto_result

          append_judge_synthesis(feedback:, code:, context:)
          publish_confidence(feedback)
          Master::Result.ok(feedback)
        rescue StandardError => e
          Master::Result.err("council: #{e.message}", category: :unknown)
        end

        private

        # Parallel fan-out — all personas in flight at once, bounded by MAX_CONCURRENT.
        def collect_parallel(code:, context:, personas: @personas)
          return [] if circuit_open?
          slots = Mutex.new
          available = MAX_CONCURRENT
          ready = ConditionVariable.new

          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + TOTAL_BUDGET_S
          threads = personas.map do |persona|
            Thread.new do
              slots.synchronize { ready.wait(slots) until available > 0; available -= 1 }
              begin
                ask_persona(persona:, code:, context:)
              ensure
                slots.synchronize { available += 1; ready.broadcast }
              end
            end
          end
          threads.filter_map { |t| join_or_kill(t, deadline) }
        end

        # Sequential handoff — each persona sees prior personas' feedback as context.
        # Slower than parallel but lets personas react to each other rather than
        # all speaking in isolation. Use when reactions and rebuttals matter more
        # than independent reads.
        def collect_sequential(code:, context:, personas: @personas)
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + TOTAL_BUDGET_S
          acc = []
          personas.each do |persona|
            break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
            break if circuit_open?
            turn_ctx = acc.empty? ? context : "#{context}\n\nprior turns:\n#{format_prior_turns(acc)}"
            entry = ask_persona(persona:, code:, context: turn_ctx)
            acc << entry if entry
          end
          acc
        end

        # Returns a Result::Err if any veto-eligible persona issued a VETO, else nil.
        def enforce_veto(feedback)
          vetoes = feedback.select { |f| f[:veto_role] && veto_text?(f[:feedback]) }
          return nil if vetoes.empty?
          veto = vetoes.first
          @bus&.publish(:council_veto, veto)
          Master::Result.err("council: veto from #{veto[:persona]}\n#{veto[:feedback]}", category: :validation)
        end

        # Append judge synthesis entry to feedback when judge is enabled.
        def append_judge_synthesis(feedback:, code:, context:)
          synthesis = @judge_enabled ? judge(feedback:, code:, context:) : nil
          return unless synthesis
          @bus&.publish(:council_synthesis, synthesis: synthesis)
          feedback << { persona: "Judge", role: "Synthesis", veto_role: false,
                        axiom: nil, feedback: synthesis }
        end

        # Compute mean confidence and publish the council_confidence event.
        def publish_confidence(feedback)
          scores = feedback.filter_map { |f| f[:confidence] }
          council_confidence = scores.empty? ? 0.5 : scores.sum / scores.size
          @bus&.publish(:council_confidence, score: council_confidence.round(3), members: feedback.size)
        end

        def circuit_open?
          breaker = @agent.respond_to?(:circuit_breaker) ? @agent.circuit_breaker : nil
          return false unless breaker.respond_to?(:open_models)
          !breaker.open_models.empty?
        rescue StandardError
          false
        end

        def ask_persona(persona:, code:, context:)
          prompt = build_prompt(persona:, code:, context:)
          model = persona.respond_to?(:model) ? persona.model : nil
          response = model ? @agent.ask_once(prompt, model: model) : @agent.ask(prompt)
          entry = { persona: persona.name, role: persona.role,
                    veto_role: veto_role?(persona), axiom: primary_axiom(persona),
                    model: model, feedback: response, confidence: score_confidence(response) }
          @bus&.publish(:council_feedback, entry)
          entry
        rescue StandardError => e
          @bus&.publish("council:persona_error", persona: persona.name, error: e.message)
          nil
        end

        def format_prior_turns(entries)
          entries.map { |e| "#{e[:persona]} (#{e[:role]}): #{e[:feedback].to_s.lines.first(3).join.strip}" }.join("\n\n")
        end

        def join_or_kill(thread, deadline)
          remaining = [deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC), 0.1].max
          thread.join(remaining) ? thread.value : (thread.kill; nil)
        end

        def converged?(prev, curr)
          return false if prev.empty? || curr.empty? || prev.size != curr.size
          prev_texts = prev.map { |f| f[:feedback].to_s }
          curr_texts = curr.map { |f| f[:feedback].to_s }
          same = curr_texts.zip(prev_texts).count { |c, p| text_similarity(c, p) >= CONVERGENCE_TEXT_SIM }
          same.to_f / curr_texts.size >= CONVERGENCE_OVERLAP
        end

        def text_similarity(a, b)
          return 0.0 if a.empty? || b.empty?
          sa = a.downcase.scan(/\w+/).uniq
          sb = b.downcase.scan(/\w+/).uniq
          union = (sa | sb).size
          union.zero? ? 0.0 : (sa & sb).size.to_f / union
        end

        def feedback_summary(feedback, base_context)
          lines = feedback.reject { |f| f[:persona] == "Judge" }.map do |f|
            "#{f[:persona]} (#{f[:role]}): #{f[:feedback].to_s.lines.first(2).join.strip}"
          end
          summary = "\nprior round:\n" + lines.join("\n") + "\n"
          [base_context, summary].compact.join
        end

        def judge(feedback:, code:, context:)
          prompt = build_judge_prompt(feedback:, code:, context:)
          @agent.ask(prompt)
        rescue StandardError => e
          @bus&.publish(:council_judge_error, error: e.message)
          nil
        end

        PROMPTS_PATH = File.join(Master::ROOT, "data", "prompts", "council.yml").freeze

        def self.prompts
          @prompts ||= Master.load_yaml(PROMPTS_PATH) || {}
        end

        def build_judge_prompt(feedback:, code:, context: nil)
          rounds = feedback.map { |f| format_round(f) }.join("\n\n")
          format(self.class.prompts.fetch("judge"),
                 quality_brief: self.class.quality_brief(:general),
                 rounds: rounds)
        end

        def format_round(f)
          axiom_tag = f[:axiom] ? "[#{f[:axiom]}] " : ""
          "#{axiom_tag}#{f[:persona]} (#{f[:role]}): #{f[:feedback]}"
        end

        def primary_axiom(persona)
          ids = persona.respond_to?(:emphasizes) ? Array(persona.emphasizes) : []
          ids.first
        end

        def axiom_line(persona)
          id = primary_axiom(persona)
          return "" unless id && @rules
          name = @rules.lookup(id)
          name ? "You speak primarily for the #{id} axiom: #{name}." : ""
        end

        def validate_dependencies!
          raise ArgumentError, "personas must be an array" unless @personas.is_a?(Array)
          raise ArgumentError, "agent must respond to :ask" unless @agent.respond_to?(:ask)
        end

        def veto_role?(persona)
          if persona.respond_to?(:veto?)
            persona.veto?
          else
            persona.respond_to?(:veto_role) && !!persona.veto_role
          end
        end

        def build_prompt(persona:, code:, context:)
          ctx = context ? "\nContext: #{context}\n" : ""
          veto_hint = veto_role?(persona) ? " You may prefix VETO: if this must not ship." : ""
          safe_code = truncate_code(code.to_s)
          axiom = axiom_line(persona)
          axiom_block = axiom.empty? ? "" : "#{axiom}\n"
          quality_block = self.class.quality_brief(QualityFramework.domain_for(persona.name))
          question = self.class.sample_question(persona)
          question_block = question ? "\nAdversarial question for this turn: #{question}\n" : ""
          format(self.class.prompts.fetch("juror"),
                 persona_name: persona.name, persona_role: persona.role,
                 persona_bias: persona.bias, persona_prompt: persona.prompt,
                 ctx: ctx, axiom_block: axiom_block, quality_block: quality_block,
                 question_block: question_block, safe_code: safe_code, veto_hint: veto_hint)
        end

        def truncate_code(code)
          return code if code.bytesize <= MAX_CODE_BYTES
          @bus&.publish(:council_code_truncated, bytes: code.bytesize, limit: MAX_CODE_BYTES)
          code.byteslice(0, MAX_CODE_BYTES) + TRUNCATE_MARKER
        end

        VETO_RE = /\AVETO:/i.freeze

        def veto_text?(feedback)
          VETO_RE.match?(feedback.to_s.strip)
        end

        HIGH_CONF = /\b(certain|clearly|definitely|must|always|never|critical|serious)\b/i.freeze
        LOW_CONF = /\b(maybe|possibly|perhaps|unclear|might|could|unsure|uncertain)\b/i.freeze

        def score_confidence(text)
          t = text.to_s
          highs = t.scan(HIGH_CONF).size
          lows  = t.scan(LOW_CONF).size
          total = highs + lows
          return 0.5 if total.zero?
          (0.5 + (highs - lows).to_f / (total * 2)).clamp(0.1, 0.95)
        end
      end
    end
  end
end
