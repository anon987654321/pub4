# frozen_string_literal: true

module Master
  module Judge
    module Council
      module DeliberationSynthesis
        private

        def enforce_veto(feedback)
          veto = feedback.find { |entry| entry[:veto_role] && veto_text?(entry[:feedback]) }
          return unless veto

          @bus&.publish(:council_veto, veto)
          Result.err("council: veto from #{veto[:persona]}\n#{veto[:feedback]}", category: :validation)
        end

        def append_judge_synthesis(feedback:, code:, context:)
          synthesis = @judge_enabled ? judge(feedback:, code:, context:) : nil
          return unless synthesis

          @bus&.publish(:council_synthesis, synthesis:)
          feedback << { persona: "Judge", role: "Synthesis", veto_role: false, axiom: nil, feedback: synthesis }
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

        def judge(feedback:, code:, context:)
          @agent.ask(build_judge_prompt(feedback:, code:, context:))
        rescue StandardError => e
          @bus&.publish(:council_judge_error, error: e.message)
          nil
        end
      end
    end
  end
end
