# frozen_string_literal: true

module Master
  module Judge
  module Council
    module QualityFramework
      DEFAULT_QUESTIONS = {
        "assumptions" => [
          "what are we assuming that could be false?",
          "if a key assumption flips what still works?",
          "which assumptions have we never tested?",
          "what would happen if the opposite were true?",
          "which assumptions are load-bearing vs convenience?",
          "how do we validate assumptions incrementally?"
        ],
        "failure_modes" => [
          "how does this fail catastrophically?",
          "what breaks first under load or outage?",
          "which single point of failure is most likely?",
          "what happens when it fails silently?",
          "how do cascading failures propagate?",
          "what are blast radius containment strategies?"
        ],
        "attacker" => [
          "what would an attacker do here?",
          "where can inputs be abused or poisoned?",
          "which trust boundaries are weakest?",
          "how would we exploit this ourselves?",
          "what attack vectors are we not considering?",
          "how do we defend against insider threats?"
        ],
        "scale" => [
          "what happens at 10x users or data?",
          "what performance cliff exists and where?",
          "which bottleneck appears first?",
          "how does complexity grow with scale?",
          "what are the economics at different scales?",
          "which architectural decisions become problematic at scale?"
        ],
        "degradation" => [
          "how do we degrade gracefully?",
          "what is minimal viable behavior under stress?",
          "which features can we sacrifice first?",
          "how do we maintain core function during failure?",
          "what are UX implications of degradation?",
          "how do we communicate degraded service to users?"
        ],
        "edge_cases" => [
          "which edge cases will users hit first?",
          "which rare but high-impact case is unhandled?",
          "what happens with malformed inputs?",
          "how do we handle impossible combinations?",
          "which edge cases become common at scale?",
          "what edge cases exist in integration points?"
        ],
        "ops_maint" => [
          "what is long-term maintenance burden?",
          "how do we observe debug and rollback quickly?",
          "which operational complexity is hidden?",
          "how do we troubleshoot under pressure?",
          "what skills and knowledge are required for operations?",
          "how do we prevent operational knowledge from being siloed?"
        ],
        "compliance_ethics" => [
          "any privacy safety or fairness risks?",
          "which regulations apply and how prove compliance?",
          "what are ethical implications?",
          "how audit and demonstrate adherence?",
          "what happens when regulations change?",
          "how balance compliance with innovation?"
        ],
        "a11y_ux" => [
          "is it operable by keyboard and screen readers?",
          "what happens with reduced motion or low bandwidth?",
          "how does this work for colorblind users?",
          "can this be used with assistive technology?",
          "what are multilingual and cultural considerations?",
          "how test accessibility with actual users?"
        ],
        "economics" => [
          "where is waste or needless complexity?",
          "what is ROI vs simpler alternatives?",
          "which costs are hidden or deferred?",
          "how optimize for total cost of ownership?",
          "what are opportunity costs of this approach?",
          "how do economics change over time and scale?"
        ],
        "clarity" => [
          "is the intent obvious from names alone?",
          "which concept lacks a name and should have one?",
          "where does the code lie about what it does?",
          "what would a fresh reader misread first?",
          "which generic names hide domain meaning?"
        ],
        "evidence" => [
          "what evidence proves this works?",
          "which test would fail if this were wrong?",
          "what claim is unsupported?",
          "what would falsify this approach?"
        ],
        "scope" => [
          "what can be deleted without loss?",
          "which abstraction is premature?",
          "what is the smallest reversible change?",
          "where did implementation exceed the need?"
        ],
        "bottlenecks" => [
          "where is the Big-O bottleneck?",
          "what allocates in the hot path?",
          "what happens to latency at p95 and p99?",
          "which work can be skipped, cached, streamed, or deferred?"
        ],
        "consistency" => [
          "where can data go inconsistent?",
          "what is the source of truth?",
          "which names describe the same concept?",
          "which migration or state transition is not reversible?"
        ],
        "harm" => [
          "who could this harm if misused?",
          "what privacy boundary is crossed?",
          "what content or user data must remain untouched?",
          "what compliance proof would be required?"
        ],
        "visual" => [
          "where does the eye land first, and is that the right place?",
          "which element can be removed without losing meaning?",
          "does spacing prove grouping, or only decorate?",
          "which values violate the type scale, grid, or contrast rules?",
          "does the layout use absence as material?"
        ],
        "sound" => [
          "what should be foreground, background, or silent?",
          "does timing breathe, or is everything quantized to death?",
          "could sound mask speech, screen readers, or the user's task?",
          "is there a mute path and graceful media failure?",
          "which sound event communicates state instead of decoration?"
        ]
      }.freeze

      BRIEFS = {
        general: [
          "questions over commands; evidence over opinion; execution over explanation",
          "content integrity, critical security, accessibility, and reversibility are hard gates",
          "prefer surgical, reversible changes; preserve working behavior and user-curated content",
          "generate alternatives, red-team assumptions, then cherry-pick the simplest validated option"
        ].freeze,
        code: [
          "DRY after the third duplication; KISS when complexity exceeds 10; YAGNI for unused constructs",
          "SOLID boundaries: one reason to change, composition over inheritance, injected dependencies",
          "Ruby style: guard clauses, semantic names, no generic manager/handler/util names",
          "quality targets: complexity <= 10, nesting <= 4, duplication <= 3%, coverage >= 80%"
        ].freeze,
        design: [
          "typography is design: 45-75ch lines, 1.4-1.6 body leading, 16px minimum body text",
          "use an 8px spacing rhythm, 12-column structure, 44px touch minimum, and visible focus",
          "ultraminimalism: remove ornament until only hierarchy, alignment, type, and whitespace remain",
          "limit palette and type variety; reject non-token visual values and arbitrary decoration"
        ].freeze,
        sound: [
          "sound is feedback, not surprise: no autoplay without intent and mute must exist",
          "preserve silence; sounds need attack/decay/timing and must not mask speech or screen readers",
          "foreground sound is for critical state changes; midground for confirmations; background is optional",
          "prefer tiny browser-native tones/assets and graceful failure over heavy dependencies"
        ].freeze
      }.freeze

      PERSONA_DOMAIN = {
        "Graphic Designer" => :design,
        "Web Designer" => :design,
        "Motion Designer" => :design,
        "Google CSS Engineer" => :design,
        "NNGroup UX Researcher" => :design,
        "Accessibility" => :design,
        "Electronic Music Producer" => :sound,
        "Hip-Hop Producer" => :sound,
        "Sound Designer" => :sound,
        "Security" => :code,
        "Reliability" => :code,
        "Maintainer" => :code,
        "Performance" => :code,
        "QA Engineer" => :code
      }.freeze

      def self.questions
        council = if File.exist?(Deliberation::COUNCIL_PATH)
                    Master.load_yaml(Deliberation::COUNCIL_PATH).fetch("questions", {})
                  else
                    {}
                  end
        DEFAULT_QUESTIONS.merge(council) { |_key, builtin, custom| (Array(builtin) + Array(custom)).uniq }
      rescue StandardError
        DEFAULT_QUESTIONS
      end

      def self.domain_for(persona_name)
        PERSONA_DOMAIN.fetch(persona_name.to_s, :general)
      end

      def self.brief(domain = :general)
        ([*BRIEFS[:general], *BRIEFS.fetch(domain.to_sym, [])]).uniq.join("\n- ").then do |text|
          "Quality framework:\n- #{text}"
        end
      end
    end

    class Deliberation
      MAX_CONCURRENT       = 4
      MAX_CODE_BYTES       = 8_192
      TRUNCATE_MARKER      = "\n... [truncated to #{MAX_CODE_BYTES} bytes for review]".freeze
      JUDGE_TIMEOUT        = 30
      TOTAL_BUDGET_S       = 120
      MIN_QUORUM           = 3
      CONVERGENCE_ROUNDS   = 3
      CONVERGENCE_OVERLAP  = 0.7
      CONVERGENCE_TEXT_SIM = 0.6

      COUNCIL_PATH = File.join(Master::ROOT, "data", "council.yml").freeze

      # Maps each council persona to the question bank category they draw from.
      PERSONA_QUESTION = {
        "Architect"                 => "assumptions",
        "Data Steward"              => "consistency",
        "Ethics & Policy"           => "harm",
        "Maintainer"                => "clarity",
        "Performance"               => "bottlenecks",
        "Product Strategist"        => "economics",
        "QA Engineer"               => "evidence",
        "Pragmatist"                => "scope",
        "Reliability"               => "failure_modes",
        "Security"                  => "attacker",
        "Skeptic"                   => "failure_modes",
        "User"                      => "edge_cases",
        "User Advocate"             => "edge_cases",
        "Accessibility"             => "a11y_ux",
        "Layperson"                 => "clarity",
        "Mentor"                    => "clarity",
        "Graphic Designer"          => "visual",
        "Web Designer"              => "visual",
        "Motion Designer"           => "visual",
        "Google CSS Engineer"       => "visual",
        "NNGroup UX Researcher"     => "a11y_ux",
        "Electronic Music Producer" => "sound",
        "Hip-Hop Producer"          => "sound",
        "Sound Designer"            => "sound"
      }.freeze

      @questions = nil

      def self.questions
        @questions ||= QualityFramework.questions
      end

      def self.sample_question(persona_name)
        cat = PERSONA_QUESTION[persona_name.to_s]
        bank = questions[cat]
        bank&.sample
      end

      def self.quality_brief(domain = :general)
        QualityFramework.brief(domain)
      end

      def initialize(personas:, agent:, event_bus: nil, axioms: nil, judge_enabled: true)
        @personas      = personas
        @agent         = agent
        @bus           = event_bus
        @rules         = axioms
        @judge_enabled = judge_enabled
        validate_dependencies!
      end

      def review_convergent(code, context: nil, max_rounds: CONVERGENCE_ROUNDS)
        history = []
        round_context = context
        max_rounds.times do |i|
          @bus&.publish(:council_round_start, round: i + 1, max: max_rounds)
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
                        feedback: response, confidence: score_confidence(response) }
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
          quorum_msg = "council: quorum not reached (#{feedback.size}/#{@personas.size})"
          return Master::Result.err(quorum_msg, category: :timeout)
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

        scores = feedback.filter_map { |f| f[:confidence] }
        council_confidence = scores.empty? ? 0.5 : scores.sum / scores.size
        @bus&.publish(:council_confidence, score: council_confidence.round(3), members: feedback.size)
        Master::Result.ok(feedback)
      rescue StandardError => e
        Master::Result.err("council: #{e.message}", category: :unknown)
      end

      private

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
          axiom. Extract the load-bearing critique, drop redundancy, surface unresolved
          disagreement.

          #{self.class.quality_brief(:general)}

          Jurors:
          #{rounds}

          Classify the finding:
          - TRIVIAL (safe to auto-fix): output exactly → AUTOFIX: <one-line description of the fix>
          - NON-TRIVIAL (needs a decision): output exactly →
              ISSUE: <one sentence>
              OPTION 1: <approach and trade-off>
              OPTION 2: <approach and trade-off>
              OPTION 3: <approach and trade-off>
              RECOMMEND: <which option and why in one sentence>

          Non-trivial if: spans more than one file, touches architecture, security, accessibility, privacy, or user content integrity.
          3-8 lines total. No preamble.
        PROMPT
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

      def build_prompt(persona, code, context)
        ctx = context ? "\nContext: #{context}\n" : ""
        veto_hint = veto_role?(persona) ? " You may prefix VETO: if this must not ship." : ""
        safe_code = truncate_code(code.to_s)
        axiom = axiom_line(persona)
        axiom_block = axiom.empty? ? "" : "#{axiom}\n"
        quality_block = self.class.quality_brief(QualityFramework.domain_for(persona.name))
        question = self.class.sample_question(persona.name)
        question_block = question ? "\nAdversarial question for this turn: #{question}\n" : ""
        <<~PROMPT
          You are #{persona.name} (#{persona.role}, bias: #{persona.bias}).#{ctx}
          #{axiom_block}#{quality_block}
          #{persona.prompt}#{question_block}
          Code:
          #{safe_code}

          Provide terse, actionable feedback. Prefer reversible fixes.#{veto_hint}
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