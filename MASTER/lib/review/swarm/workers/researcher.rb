# frozen_string_literal: true

module Master
  module Review
    module Swarm
      module Workers
        # Synthesizes research from external sources. No codebase context.
        class Researcher < Worker
          PREFERRED_MODEL = "google/gemini-2.0-flash-lite:free".freeze
          FALLBACK_MODEL = "openrouter/auto".freeze

          CONFIDENCE_MAP = { "high" => 0.9, "med" => 0.6, "medium" => 0.6, "low" => 0.3 }.freeze

          private

          def role_description
            "You are a research analyst. Synthesize information concisely. " \
              "Output JSON: {summary: string, sources: [string], confidence: \"low\"|\"med\"|\"high\"}"
          end

          def build_prompt(task, ctx)
            parts = []
            parts << "Domain: #{ctx[:domain]}" if ctx[:domain]
            parts << "Prior findings:\n#{ctx[:prior_findings]}" if ctx[:prior_findings]
            parts << "Research: #{task}"
            parts.join("\n\n")
          end

          def parse_result(raw)
            text = raw.to_s.strip
            parsed = JSON.parse(text.match(/\{.*\}/m)&.to_s || "{}")
            summary = parsed["summary"] || text
            sources = Array(parsed["sources"])
            conf_key = parsed["confidence"].to_s.downcase
            conf = CONFIDENCE_MAP.fetch(conf_key, nil) || uncertainty_confidence(text)
            Result.ok({ summary:, sources:, confidence: conf })
          rescue JSON::ParserError
            Result.ok({ summary: text, sources: [], confidence: uncertainty_confidence(text) })
          end
        end
      end
    end
  end
end
