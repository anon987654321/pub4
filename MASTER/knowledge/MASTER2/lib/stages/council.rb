# frozen_string_literal: true

module MASTER
  module Stages
    # Stage 5: Adversarial council review (delegates to Council)
    class Council
      # Keywords indicating code-related queries that warrant council review
      CODE_RELATED_PATTERN = /\b(fix|refactor|debug|code|script|function|class|method|file|write|implement|build|deploy|test|security|sql|shell|command)\b/i

      # Security/safety keywords in veto reasons that escalate to hard warning
      SECURITY_VETO_KEYWORDS = /\b(auth|authentication|authorization|injection|xss|csrf|token|credential|password|secret|api.key|rate.limit|sanitize|escape|unsafe|privilege|exploit|attack|vulnerability)\b/i

      def call(input)
        if defined?(Logging)
          Logging.dmesg_log("council0", parent: "pipeline0", message: "ENTER council",
                                        level: Logging::ALL_EVENTS)
        end
        text = input[:text] || ""
        model = input[:model]
        return Result.ok(input) unless model

        # Skip council for non-code queries (reduce latency for simple questions)
        unless code_related?(text)
          if defined?(Logging)
            Logging.dmesg_log("council0", message: "skipped: non-code query",
                                          level: Logging::ALL_EVENTS)
          end
          return Result.ok(input)
        end

        # iMAD: only invoke council when primary response shows uncertainty
        if defined?(LLM::HesitationDetector)
          hesitation = LLM::HesitationDetector.evaluate(input[:response].to_s, context: "pipeline_council")
          !hesitation[:escalate]
        end

        # NOTE: model: param is accepted by Council.council_review but currently unused
        review = MASTER::Council.council_review(text, model: model)
        security_veto = security_veto?(review[:votes] || [])

        Result.ok(input.merge(
                    council_verdict: review[:verdict],
                    council_vetoed: review[:vetoed_by].any?,
                    council_vetoes: review[:vetoed_by],
                    council_votes: review[:votes],
                    council_security_veto: security_veto,
                  ))
      end

      private

      def code_related?(text)
        CODE_RELATED_PATTERN.match?(text)
      end

      # True when any veto reason contains security-relevant keywords
      def security_veto?(votes)
        votes.any? { |v| v[:veto] && SECURITY_VETO_KEYWORDS.match?(v[:reason].to_s) }
      end
    end
  end
end
