# frozen_string_literal: true

module MASTER
  module Stages
    # Stage 1: Pass text through, enrich with memory context, flag for elicitation.
    # Implements gist items #7 (elicitation) and #10 (memory triggers).
    class Intake
      def call(input)
        text = input[:text] || ""
        enriched = input.merge(text: text)

        # Classify all signals via NLU (LLM with deterministic fallback)
        signals = if defined?(MASTER::NLU)
                    MASTER::NLU.classify_signals(text)
                  else
                    Set.new
                  end
        enriched = enriched.merge(signals: signals)

        # Auto-enrich with semantic memory if trigger words detected
        if signals.include?(:memory_trigger) && defined?(MASTER::Session)
          history = begin
            MASTER::Session.current&.recent_messages(3) || []
          rescue StandardError
            []
          end
          enriched = enriched.merge(memory_context: history) unless history.empty?
        end

        # Flag complex/ambiguous requests for elicitation checkpoint in REPL
        if signals.include?(:complex_task) && !signals.include?(:simple_command)
          enriched = enriched.merge(needs_elicitation: true)
        end

        # NLU: structured intent for executor routing
        if defined?(MASTER::NLU) && !text.empty?
          nlu = MASTER::NLU.parse(text, context: input[:memory_context] || {})
          enriched = enriched.merge(nlu_intent: nlu) unless nlu[:intent] == :unknown
        end

        Result.ok(enriched)
      end
    end
  end
end
