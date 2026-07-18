# frozen_string_literal: true

module Master
  module Review
    module Swarm
      module Workers
        # Reads code, produces structured analysis. Knows nothing about other workers.
        class Analyst < Worker
          PREFERRED_MODEL = "google/gemini-2.0-flash-lite:free".freeze
          FALLBACK_MODEL = "openrouter/auto".freeze
          private

          def role_description
            "You analyze code for quality, bugs, and design issues. " \
              "Output JSON: {issues: [{file, line, severity(1-3), description}], summary: string}"
          end

          def build_prompt(task, ctx)
            parts = []
            parts << "File: #{ctx[:file]}" if ctx[:file]
            parts << "Code:\n```\n#{ctx[:code]}\n```" if ctx[:code]
            parts << "Analyze: #{task}"
            parts.join("\n\n")
          end

          def parse_result(raw)
            match_str = raw.to_s.match(/\{.*\}/m)&.to_s || "{}"
            parsed = JSON.parse(match_str)
            Result.ok(parsed)
          rescue JSON::ParserError => _e
            Result.ok({ summary: raw.to_s.strip, issues: [] })
          end
        end
      end
    end
  end
end
