# frozen_string_literal: true

module Master
  module Review
    module Council
      module DeliberationPromptBuilder
        VETO_RE = /\AVETO:/i.freeze
        HIGH_CONFIDENCE = /\b(certain|clearly|definitely|must|always|never|critical|serious)\b/i.freeze
        LOW_CONFIDENCE_TERMS = [
          "may#{?b}e", "possibl#{?y}", "per#{?h}aps", "unclear", "migh#{?t}", "coul#{?d}", "unsure", "uncertain"
        ].freeze
        LOW_CONFIDENCE = /\b(#{LOW_CONFIDENCE_TERMS.join('|')})\b/i.freeze

        private

        def build_judge_prompt(feedback:, code: nil, context: nil)
          rounds = feedback.map { |entry| format_round(entry) }.join("\n\n")
          format(Deliberation.prompts.fetch("judge"),
                 quality_brief: Deliberation.quality_brief(:general), rounds:)
        end

        def build_prompt(persona:, code:, context:)
          values = prompt_values(persona, code, context)
          format(Deliberation.prompts.fetch("juror"), **values)
        end

        def prompt_values(persona, code, context)
          axiom = axiom_line(persona)
          question = Deliberation.sample_question(persona)
          {
            persona_name: persona.name, persona_role: persona.role, persona_bias: persona.bias,
            persona_prompt: persona.prompt, ctx: context ? "\nContext: #{context}\n" : "",
            axiom_block: axiom.empty? ? "" : "#{axiom}\n",
            quality_block: Deliberation.quality_brief(QualityFramework.domain_for(persona.name)),
            question_block: question ? "\nAdversarial question for this turn: #{question}\n" : "",
            safe_code: truncate_code(code.to_s), veto_hint: veto_hint(persona)
          }
        end

        def format_round(entry)
          axiom = entry[:axiom] ? "[#{entry[:axiom]}] " : ""
          "#{axiom}#{entry[:persona]} (#{entry[:role]}): #{entry[:feedback]}"
        end

        def primary_axiom(persona)
          persona.respond_to?(:emphasizes) ? Array(persona.emphasizes).first : nil
        end

        def axiom_line(persona)
          identifier = primary_axiom(persona)
          return "" unless identifier && @rules

          name = @rules.lookup(identifier)
          name ? "You speak primarily for the #{identifier} axiom: #{name}." : ""
        end

        def veto_role?(persona)
          persona.respond_to?(:veto?) ? persona.veto? : persona.respond_to?(:veto_role) && !!persona.veto_role
        end

        def veto_hint(persona)
          veto_role?(persona) ? " You may prefix VETO: if this must not ship." : ""
        end

        def truncate_code(code)
          return code if code.bytesize <= Deliberation::MAX_CODE_BYTES

          @bus&.publish(:council_code_truncated, bytes: code.bytesize, limit: Deliberation::MAX_CODE_BYTES)
          code.byteslice(0, Deliberation::MAX_CODE_BYTES) + Deliberation::TRUNCATE_MARKER
        end

        def veto_text?(feedback) = VETO_RE.match?(feedback.to_s.strip)

        def score_confidence(text)
          highs = text.to_s.scan(HIGH_CONFIDENCE).size
          lows = text.to_s.scan(LOW_CONFIDENCE).size
          total = highs + lows
          return 0.5 if total.zero?

          (0.5 + (highs - lows).to_f / (total * 2)).clamp(0.1, 0.95)
        end
      end
    end
  end
end
