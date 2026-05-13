# frozen_string_literal: true

module Master
  module Judge
  module Scan
    module Rules
      require_relative "../finding"
      # LLM review for rules whose violations resist lexical detection.
      # Each rules.yml entry with a detect_semantic prompt is folded into one LLM
      # call per file. Rules carry mode: violation (default) or opportunity —
      # the prompt frame and severity follow from that.
      class SemanticRule < Rule
        RULES_PATH = File.join(Master::ROOT, "data", "rules.yml").freeze
        CODE_SNIPPET_LIMIT = 2000

        def initialize(agent: nil)
          super()
          @agent       = agent
          @id          = "semantic"
          @description = "LLM-based rule review (violations + opportunities)"
          @severity    = :warning
          @rules      = load_semantic_rules
          @rule_tags  = @rules.keys.map(&:to_sym)
        end

        def self.auto_build? = false

        def set_agent(agent)
          @agent = agent
          self
        end

        def check(code, path:)
          return [] unless language(path) && @agent

          response = @agent.ask(build_prompt(code, path), operation: :scan_semantic).to_s
          parse_findings(response)
        rescue StandardError => e
          [finding(line: 1, message: "semantic: scan error — #{e.message}")]
        end

        private

        # Each axiom is { prompt:, severity:, mode: }. info-tier violations stay
        # out of the prompt — they're noise that doubles cost. info-tier
        # opportunities stay in: that's their whole point.
        def load_semantic_rules
          data = Master.load_yaml(RULES_PATH)
          (data["rules"] || {}).values.flatten
            .select { |r| r["detect_semantic"] }
            .reject { |r| r["severity"] == "info" && r["mode"] != "opportunity" && r["tier"] != "kernel" }
            .each_with_object({}) do |r, h|
              h[r["id"]] = {
                prompt: r["detect_semantic"],
                severity: (r["severity"] || "warning").to_sym,
                mode: (r["mode"] || "violation").to_sym
              }
            end
        end

        def build_prompt(code, path)
          violations = @rules.select { |_, a| a[:mode] == :violation }
          opportunities = @rules.select { |_, a| a[:mode] == :opportunity }
          parts = []
          parts << violation_block(violations) unless violations.empty?
          parts << opportunity_block(opportunities) unless opportunities.empty?
          <<~PROMPT
            Review #{File.basename(path)}.

            #{parts.join("\n\n")}

            Code (first #{CODE_SNIPPET_LIMIT} chars):
            #{code[0, CODE_SNIPPET_LIMIT]}
          PROMPT
        end

        def violation_block(rules)
          list = rules.map { |id, a| "#{id}: #{a[:prompt]}" }.join("\n")
          <<~BLOCK
            VIOLATIONS — list ONLY clear breaches. Format: RULE_ID:LINE:description.
            If clean, write CLEAN on its own line.
            #{list}
          BLOCK
        end

        def opportunity_block(rules)
          list = rules.map { |id, a| "#{id}: #{a[:prompt]}" }.join("\n")
          <<~BLOCK
            OPPORTUNITIES — list refactors only if they would simplify. Format: RULE_ID:LINE:reason.
            If none, write NONE on its own line.
            #{list}
          BLOCK
        end

        def parse_findings(response)
          response.lines.filter_map do |line|
            stripped = line.strip
            next if stripped.empty? || %w[CLEAN NONE].include?(stripped.upcase)

            match = stripped.match(/\A([A-Z_][A-Z0-9_]*):(\d+):(.+)\z/)
            next unless match && @rules.key?(match[1])

            axiom = @rules[match[1]]
            Finding.build(
              rule: match[1].downcase,
              message: match[3].strip,
              line: match[2].to_i,
              severity: axiom[:severity],
              fix: nil,
              tags: [match[1].to_sym, axiom[:mode]]
            )
          end
        end
      end
    end
  end
  end
end
