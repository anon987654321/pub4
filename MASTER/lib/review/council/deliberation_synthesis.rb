# frozen_string_literal: true

require_relative "../../cognition/intelligence"
require_relative "inter_model_contract"

module Master
  module Review
    module Council
      module DeliberationSynthesis
        private

        # A veto is a critical finding from a veto role. The structured answer always opens with
        # its position, so a "VETO:" prefix on the rendered text can never occur.
        def enforce_veto(feedback)
          veto = feedback.find { |entry| entry[:veto_role] && critical_finding?(entry) }
          return unless veto

          @bus&.publish(:council_veto, veto)
          Result.err("council: veto from #{veto[:persona]}\n#{veto[:feedback]}", category: :validation)
        end

        def append_judge_synthesis(feedback:, code:, context:, image: nil)
          machine = Master::Cognition::Intelligence.synthesize_judgments(feedback)
          @bus&.publish(:council_reasoning_synthesis, synthesis: machine)

          result = @judge_enabled ? judge(feedback:, code:, context:, image:) : nil
          return unless result

          synthesis = result.fetch("feedback")
          @bus&.publish(:council_synthesis, synthesis:)
          feedback << {
            persona: "Judge", role: "Synthesis", veto_role: false, axiom: nil,
            feedback: synthesis, structured_findings: result.dig("data", "findings"),
            position: result.dig("data", "position"), position_reason: result.dig("data", "position_reason"),
            cognition: machine
          }
        end

        def publish_confidence(feedback)
          scores = feedback.filter_map { |entry| entry[:confidence] }
          score = scores.empty? ? 0.5 : scores.sum / scores.size
          @bus&.publish(:council_confidence, score: score.round(3), members: feedback.size)
        end

        def converged?(previous, current)
          return false if previous.empty? || current.empty? || previous.size != current.size

          similarities = current.zip(previous).map do |now, before|
            text_similarity(now[:feedback].to_s, before[:feedback].to_s)
          end
          similarities.count { |score| score >= Deliberation::CONVERGENCE_TEXT_SIM }.to_f / current.size >=
            Deliberation::CONVERGENCE_OVERLAP
        end

        def text_similarity(first, second)
          return 0.0 if first.empty? || second.empty?

          first_words = first.downcase.scan(/\w+/).uniq
          second_words = second.downcase.scan(/\w+/).uniq
          union = (first_words | second_words).size
          union.zero? ? 0.0 : (first_words & second_words).size.to_f / union
        end

        def feedback_summary(feedback, base_context)
          lines = feedback.reject { |entry| entry[:persona] == "Judge" }.map do |entry|
            "#{entry[:persona]} (#{entry[:role]}): #{entry[:feedback].to_s.lines.first(2).join.strip}"
          end
          [base_context, "\nprior round:\n#{lines.join("\n")}\n"].compact.join
        end

        def judge(feedback:, code:, context:, image: nil)
          request_prompt = build_judge_prompt(feedback:, code:, context:)
          prior_findings = feedback.flat_map { |entry| Array(entry[:structured_findings]) }
          InterModelContract.exchange(
            prompt: request_prompt, role: "judge", bus: @bus, prior_findings:,
          ) do |outbound, _retrying|
            image ? @agent.ask(outbound, image:) : @agent.ask(outbound)
          end
        rescue StandardError => e
          @bus&.publish(:council_judge_error, error_class: e.class.name)
          nil
        end
      end
    end
  end
end
