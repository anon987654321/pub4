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
          CODE_SNIPPET_LIMIT = 2000

          def initialize(agent: nil)
            super()
            @agent = agent
            @id = "semantic"
            @description = "LLM-based rule review (violations + opportunities)"
            @severity = :warning
            @cache = {}
            reload_semantic_rules!
          end

          def self.auto_build? = false

          def set_agent(agent)
            @agent = agent
            self
          end

          def check(code, path:)
            return [] unless language(path) && @agent

            reload_semantic_rules_if_stale
            cache_key = semantic_cache_key(path, code)
            return @cache[cache_key] if @cache.key?(cache_key)

            response = @agent.ask(build_prompt(code, path), operation: :scan_semantic).to_s
            findings = parse_findings(response)
            @cache[cache_key] = findings
            findings
          rescue StandardError => e
            return [] if e.message.to_s =~ /missing configuration|api.?key|unauthorized|no.*provider/i
          end

          private

          # Each axiom is { prompt:, severity:, mode: }. info-tier violations stay
          # out of the prompt — they're noise that doubles cost. info-tier
          # opportunities stay in: that's their whole point.
          def reload_semantic_rules!
            @rules = load_semantic_rules
            @rule_tags = @rules.keys.map(&:to_sym)
            @rules_mtime = rules_mtime
            @prompt_frame = build_prompt_frame
          end

          def reload_semantic_rules_if_stale
            reload_semantic_rules! if @rules_mtime != rules_mtime
          end

          def rules_mtime
            File.mtime(Master::RULES_PATH).to_i
          rescue StandardError
            nil
          end

          def semantic_cache_key(path, code)
            require "digest"
            [path, File.mtime(path).to_i, Digest::SHA256.hexdigest(code)[0, 16], @rules_mtime].join(":")
          rescue StandardError
            [path, code.bytesize, @rules_mtime].join(":")
          end

          def load_semantic_rules
            data = Master.load_rules
            flatten_rules(data["rules"])
              .select { |r| r["detect_semantic"] }
              .reject { |r| r["severity"] == "info" && r["mode"] != "opportunity" && r["tier"] != "kernel" }
              .each_with_object({}) do |r, h|
                h[r["id"]] = {
                  prompt: r["detect_semantic"],
                  severity: (r["severity"] || "warning").to_sym,
                  mode: (r["mode"] || "violation").to_sym,
                  reversibility: r["reversibility"],
                  blast_radius: r["blast_radius"],
                }
              end
          end

          def build_prompt(code, path)
            <<~PROMPT
            Review #{File.basename(path)}.

            #{@prompt_frame}

            Code (first #{CODE_SNIPPET_LIMIT} chars):
            #{code[0, CODE_SNIPPET_LIMIT]}
          PROMPT
          end

          def build_prompt_frame
            violations = @rules.select { |_, a| a[:mode] == :violation }
            opportunities = @rules.select { |_, a| a[:mode] == :opportunity }
            parts = []
            parts << violation_block(violations) unless violations.empty?
            parts << opportunity_block(opportunities) unless opportunities.empty?
            parts.join("\n\n")
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
	                rule: match[1],
                message: match[3].strip,
                line: match[2].to_i,
                severity: axiom[:severity],
                fix: nil,
	                tags: [match[1].to_sym, axiom[:mode]],
	                reversibility: axiom[:reversibility],
	                blast_radius: axiom[:blast_radius]
              )
            end
          end

          def flatten_rules(body)
            case body
            when Hash then body.values.flatten
            when Array then body
            else []
            end
          end
        end
      end
    end
  end
end
