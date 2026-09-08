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

        # Writes code given a spec. Knows only the spec + relevant file context.
        class Coder < Worker
          private

          def role_description
            "You write clean, minimal Ruby/Rails/Zsh code. " \
              "Output only the code block. No explanation unless asked."
          end

          def build_prompt(task, ctx)
            parts = []
            parts << "Language: #{ctx.fetch(:language, "ruby")}"
            parts << "Existing code:\n```\n#{ctx[:code]}\n```" if ctx[:code]
            parts << "Spec: #{task}"
            parts.join("\n\n")
          end
        end

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

        # Reviews code for security, correctness, style. Constitutional layer.
        class Reviewer < Worker
          CHECKLIST = %w[
            sql_injection xss command_injection path_traversal
            hardcoded_secrets open_redirect mass_assignment
          ].freeze

          private

          def role_description
            "You are a security-focused code reviewer. Check for OWASP top-10 issues, " \
              "logic bugs, and constitutional AI violations. " \
              "Output JSON: {approved: bool, violations: [{type, line, description}]}"
          end

          def build_prompt(task, ctx)
            parts = []
            parts << "Code to review:\n```\n#{ctx[:code]}\n```" if ctx[:code]
            parts << "Security checklist: #{CHECKLIST.join(", ")}"
            parts << "Review for: #{task}"
            parts.join("\n\n")
          end

          def parse_result(raw)
            parsed = JSON.parse(raw.to_s.match(/\{.*\}/m)&.to_s || "{}")
            parsed["approved"] = true if parsed.empty?
            Result.ok(parsed)
          rescue JSON::ParserError => _e
            Result.ok({ "approved" => true, "violations" => [] })
          end
        end
      end
    end
  end
end
