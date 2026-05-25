# frozen_string_literal: true

module Master
  module Judge
  module Swarm
    module Workers
      # Synthesizes research from external sources. No codebase context.
      class Researcher < Worker
        PREFERRED_MODEL = "google/gemini-2.0-flash-lite:free".freeze
        FALLBACK_MODEL  = "openrouter/auto".freeze
        private

        def role_description
          "You are a research analyst. Synthesize information concisely. " \
            "Output: factual summary, sources if known, confidence level (low/med/high)."
        end

        def build_prompt(task, ctx)
          parts = []
          parts << "Domain: #{ctx[:domain]}" if ctx[:domain]
          parts << "Prior findings:\n#{ctx[:prior_findings]}" if ctx[:prior_findings]
          parts << "Research: #{task}"
          parts.join("\n\n")
        end
      end
    end
  end
  end
end
