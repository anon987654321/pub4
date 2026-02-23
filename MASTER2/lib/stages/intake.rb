# frozen_string_literal: true

module MASTER
  module Stages
    # Stage 1: Pass text through, enrich with memory context, flag for elicitation.
    # Implements gist items #7 (elicitation) and #10 (memory triggers).
    class Intake
      # Gist #10: Patterns from Claude Opus/Sonnet 4.6 -- trigger automatic memory recall
      MEMORY_TRIGGERS = /\b(you suggested|we decided|last time|the bug|my project|our approach|as before|continue|what about that|as I mentioned|the strategy|the plan)\b/i

      # Gist #7: Claude for Excel elicitation pattern -- detect complex ambiguous requests
      COMPLEX_TASK = /\b(build|create|implement|redesign|migrate|architect|refactor|spawn|start|deploy|run|connect|watch|monitor|scrape|generate|write)\b.{0,80}\b(system|app|module|feature|pipeline|service|framework|agent|bot|daemon|worker|server|script|api|integration)\b/i
      SIMPLE_TASK  = /\A\s*\b(scan|fix|lint|check|test|help|version|clear|exit|quit|show|list|print|deps)\b/i

      def call(input)
        text = input[:text] || ""
        enriched = input.merge(text: text)

        # Auto-enrich with semantic memory if trigger words detected
        if text.match?(MEMORY_TRIGGERS) && defined?(MASTER::Session)
          history = begin
            MASTER::Session.current&.recent_messages(3) || []
          rescue StandardError
            []
          end
          enriched = enriched.merge(memory_context: history) unless history.empty?
        end

        # Flag complex/ambiguous requests for elicitation checkpoint in REPL
        if !text.match?(SIMPLE_TASK) && text.match?(COMPLEX_TASK)
          enriched = enriched.merge(needs_elicitation: true)
        end

        # NLU: classify intent for executor routing and context
        if defined?(MASTER::NLU) && !text.empty?
          nlu = MASTER::NLU.parse(text, context: input[:memory_context] || {})
          enriched = enriched.merge(nlu_intent: nlu) unless nlu[:intent] == :unknown
        end

        Result.ok(enriched)
      end
    end
  end
end
