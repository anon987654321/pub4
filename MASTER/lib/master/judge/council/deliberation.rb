# frozen_string_literal: true

module Master
  module Judge
  module Council
    class Deliberation
      MAX_CONCURRENT  = 4
      MAX_CODE_BYTES  = 8_192
      TRUNCATE_MARKER = "\n... [truncated to #{MAX_CODE_BYTES} bytes for review]".freeze
      JUDGE_TIMEOUT   = 30
      TOTAL_BUDGET_S  = 120
      MIN_QUORUM      = 3
      CONVERGENCE_ROUNDS = 3
      PLATEAU_OVERLAP    = 0.7
      PLATEAU_TEXT_SIM   = 0.6

      COUNCIL_PATH = File.join(Master::ROOT, "data", "council.yml").freeze
      QUESTION_CATEGORY = {
        "Architect"  => "assumptions",
        "Skeptic"    => "failure_modes",
        "Security"   => "attacker",
        "User"       => "edge_cases",
        "Pragmatist" => "economics",
        "Mentor"     => "clarity"
      }.freeze
      @questions = nil

      def self.questions
        @questions ||= begin
          data = File.exist?(COUNCIL_PATH) ? (Master.load_yaml(COUNCIL_PATH) || {}) : {}
          data["questions"] || {}
        end
      rescue StandardError
        {}
      end

      def self.sample_question(persona_name)
        cat = QUESTION_CATEGORY[persona_name.to_s]
        bank = questions[cat]
        bank&.sample
      end

      def initialize(personas:, agent:, event_bus: nil, axioms: nil, judge_enabled: true)
        @personas      = personas
        @agent         = agent
        @bus           = event_bus
        @axioms        = axioms
        @judge_enabled = judge_enabled
        validate_dependencies!
      end

      def review_convergent(code, context: nil, max_rounds: CONVERGENCE_ROUNDS)
        history = []
        round_context = context
        max_rounds.times do |i|
          @bus&.publish(:council_round_start, round: i + 1, max: max_rounds)
          result = review(code, context: round_context)
          return result unless result.is_a?(Master::Result::Ok)
          feedback = result.value!
          history << feedback
          if history.size >= 2 && plateau?(history[-2], history[-1])
            @bus&.publish(:council_converged, round: i + 1)
            break
          end
          round_context = round_digest(feedback, context)
        end
        Master::Result.ok(history.last || [])
      end

      def review(code, context: nil)
        return Master::Result.err("council: no personas configured", category: :validation) if @personas.empty?

        slots = Mutex.new
        available = MAX_CONCURRENT
        ready = ConditionVariable.new

        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + TOTAL_BUDGET_S
        threads = @personas.map do |persona|
          Thread.new do
            slots.synchronize { ready.wait(slots) until available > 0; available -= 1 }
            begin
              response = @agent.ask(build_prompt(persona, code, context))
              entry = { persona: persona.name, role: persona.role,
                        veto_role: veto_role?(persona), axiom: primary_axiom(persona),
                        feedback: response }
              @bus&.publish(:council_feedback, entry)
              entry
            rescue StandardError => e
              @bus&.publish("council:persona_error", persona: persona.name, error: e.message)
              nil
            ensure
              slots.synchronize { available += 1; ready.broadcast }
            end
          end
        end
        feedback = threads.map do |thread|
          remaining = [deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC), 0.1].max
          thread.join(remaining) ? thread.value : (thread.kill; nil)
        end.compact
        if feedback.size < MIN_QUORUM
          @bus&.publish(:council_timeout, completed: feedback.size, total: @personas.size)
          return Master::Result.err("council: quorum not reached (#{feedback.size}/#{@personas.size})", category: :timeout)
        end

        vetoes = feedback.select { |f| f[:veto_role] && veto_text?(f[:feedback]) }
        unless vetoes.empty?
          veto = vetoes.first
          @bus&.publish(:council_veto, veto)
          return Master::Result.err("council: veto from #{veto[:persona]}\n#{veto[:feedback]}", category: :validation)
        end

        synthesis = @judge_enabled ? judge(feedback, code, context) : nil
        if synthesis
          @bus&.publish(:council_synthesis, synthesis: synthesis)
          feedback << { persona: "Judge", role: "Synthesis", veto_role: false,
                        axiom: nil, feedback: synthesis }
        end

        Master::Result.ok(feedback)
      rescue StandardError => e
        Master::Result.err("council: #{e.message}", category: :unknown)
      end

      private

      def plateau?(prev, curr)
        return false if prev.empty? || curr.empty? || prev.size != curr.size
        prev_texts = prev.map { |f| f[:feedback].to_s }
        curr_texts = curr.map { |f| f[:feedback].to_s }
        same = curr_texts.zip(prev_texts).count { |c, p| jaccard(c, p) >= PLATEAU_TEXT_SIM }
        same.to_f / curr_texts.size >= PLATEAU_OVERLAP
      end

      def jaccard(a, b)
        return 0.0 if a.empty? || b.empty?
        sa = a.downcase.scan(/\w+/).uniq
        sb = b.downcase.scan(/\w+/).uniq
        union = (sa | sb).size
        union.zero? ? 0.0 : (sa & sb).size.to_f / union
      end

      def round_digest(feedback, base_context)
        lines = feedback.reject { |f| f[:persona] == "Judge" }.map do |f|
          "#{f[:persona]} (#{f[:role]}): #{f[:feedback].to_s.lines.first(2).join.strip}"
        end
        digest = "\n--- prior round ---\n" + lines.join("\n") + "\n--- end ---\n"
        [base_context, digest].compact.join
      end

      def judge(feedback, code, context)
        prompt = build_judge_prompt(feedback, code, context)
        @agent.ask(prompt)
      rescue StandardError => e
        @bus&.publish(:council_judge_error, error: e.message)
        nil
      end

      def build_judge_prompt(feedback, code, _context)
        rounds = feedback.map do |f|
          axiom_tag = f[:axiom] ? "[#{f[:axiom]}] " : ""
          "#{axiom_tag}#{f[:persona]} (#{f[:role]}): #{f[:feedback]}"
        end.join("\n\n")
        <<~PROMPT
          You are the Council judge. Each juror below speaks for a distinct constitutional
          axiom. Synthesise a single conclusion: extract the load-bearing critique,
          drop redundancy, surface unresolved disagreement explicitly, and end with one
          actionable recommendation.

          Jurors:
          #{rounds}

          Output: 3-6 lines, terse, no preamble.
        PROMPT
      end

      def primary_axiom(persona)
        ids = persona.respond_to?(:emphasizes) ? Array(persona.emphasizes) : []
        ids.first
      end

      def axiom_line(persona)
        id = primary_axiom(persona)
        return "" unless id && @axioms
        name = @axioms.lookup(id)
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

      def build_prompt(persona, code, context)
        ctx = context ? "\nContext: #{context}\n" : ""
        veto_hint = veto_role?(persona) ? " You may prefix VETO: if this must not ship." : ""
        safe_code = truncate_code(code.to_s)
        axiom = axiom_line(persona)
        axiom_block = axiom.empty? ? "" : "#{axiom}\n"
        question = self.class.sample_question(persona.name)
        question_block = question ? "\nFocus question for this turn: #{question}\n" : ""
        <<~PROMPT
          You are #{persona.name} (#{persona.role}, bias: #{persona.bias}).#{ctx}
          #{axiom_block}#{persona.prompt}#{question_block}
          Code:
          #{safe_code}

          Provide terse, actionable feedback.#{veto_hint}
        PROMPT
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
    end
  end
  end
end
