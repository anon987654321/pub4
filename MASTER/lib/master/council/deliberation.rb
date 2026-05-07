# frozen_string_literal: true

module Master
  module Council
    class Deliberation
      MAX_CONCURRENT  = 4
      MAX_CODE_BYTES  = 8_192
      TRUNCATE_MARKER = "\n... [truncated to #{MAX_CODE_BYTES} bytes for review]".freeze
      JUDGE_TIMEOUT   = 30

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

      def review(code, context: nil)
        return Master::Result.err("council: no personas configured", category: :validation) if @personas.empty?

        slots = Mutex.new
        available = MAX_CONCURRENT
        ready = ConditionVariable.new

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
        feedback = threads.map { |thread| thread.join(30) ? thread.value : nil }.compact
        if feedback.empty?
          @bus&.publish(:council_timeout, personas: @personas.map(&:name))
          return Master::Result.err("council: all personas timed out (#{@personas.size})", category: :timeout)
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