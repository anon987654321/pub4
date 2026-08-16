# frozen_string_literal: true

module Master
  module Review
    module Scan
      module Rules
        # Steelman-first red-team: the model must defend the code before it can attack it.
        # This suppresses false positives by forcing consideration of legitimate reasons
        # before a violation can survive. Deep depth only; one LLM call per file.
        class AdversarialRule < Rule
          PROMPT_TEMPLATE = <<~PROMPT.freeze
          Red-team review of %<path>s.

          Step 1 — Steelman (internal, do not output): write the three strongest
          arguments that this code is correct and should not be changed.

          Step 2 — Answer each question silently; only include findings below
          if they survive the steelman:
            1. What is wrong with this design that I have not spotted?
            2. What would an attacker do with this code?
            3. What assumption is this built on that could be false?
            4. What breaks at scale or under failure?
            5. Is this wired to anything? Could it be deleted without loss?
            6. Is there a simpler approach that was not taken?
            7. What should be relocated or transformed to a different format?

          Step 3 — Output only surviving violations.
          Format: ISSUE:LINE:description (one per line).
          If nothing survives, respond with exactly: CLEAN

          Focus on: broken contracts, hidden coupling, axiom violations (CQS,
          ONE_JOB, GUARD_EXPENSIVE, FAIL_VISIBLY), security, and logic errors.
          Ignore style. Do not hallucinate method names.

          Code (%<lang>s):
          %<code>s
        PROMPT

          def initialize(agent: nil)
            super()
            @agent = agent
            @id = "adversarial"
            @description = "Red-team scan: steelman then challenge — suppresses false positives"
            @severity = :error
            @rule_tags = %i[ONE_JOB CQS GUARD_EXPENSIVE FAIL_VISIBLY COMPOSABLE]
          end

          def self.auto_build? = false

          def set_agent(agent)
            @agent = agent
            self
          end

          def check(code, path:)
            return [] unless @agent
            return [] unless (lang = language(path))

            prompt = format(PROMPT_TEMPLATE, path: File.basename(path),
                                             lang:,
                                             code: code[0, 3_000])
            response = @agent.ask(prompt, operation: :scan_adversarial).to_s
            parse_findings(response)
          rescue StandardError => e
            [] if e.message.to_s =~ /missing configuration|api.?key|unauthorized|no.*provider/i
          end

          private

          def parse_findings(response)
            response_normalized = response.strip.upcase
            return [] if response_normalized.start_with?("CLEAN")

            response.lines.filter_map do |line|
              match = line.strip.match(/\AISSUE:(\d+):(.+)\z/)
              next unless match
              finding(line: match[1].to_i, message: "adversarial: #{match[2].strip}")
            end
          end
        end
      end
    end
  end
end

module Master
  module Review
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
            [] if e.message.to_s =~ /missing configuration|api.?key|unauthorized|no.*provider/i
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
            File.exist?(Master::RULES_PATH) ? File.mtime(Master::RULES_PATH).to_i : nil
          end

          def semantic_cache_key(path, code)
            require "digest"
            [path, File.mtime(path).to_i, Digest::SHA256.hexdigest(code)[0, 16], @rules_mtime].join(":")
          rescue StandardError
            [path, code.bytesize, @rules_mtime].join(":")
          end

          def load_semantic_rules
            data = Master.load_rules
            Master.flatten_rules(data["rules"])
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
                blast_radius: axiom[:blast_radius],
              )
            end
          end

        end
      end
    end
  end
end

module Master
  module Review
    module Scan
      module Rules
        # Comments above method defs that no longer describe what the code does.
        # Lexical pass extracts (comment, method_body) pairs; LLM judges drift in one
        # batched call per file. Pairs with the "reassess on touch" directive: lying
        # comments are factual bugs, not style noise.
        class CommentDriftRule < Rule
          MAX_PAIRS_PER_FILE = 8
          # Lines of method body sent to LLM for drift comparison.
          BODY_SNIPPET = 20

          def initialize(agent: nil)
            super()
            @agent = agent
            @id = "comment_drift"
            @description = "Comment claim doesn't match method body — comment is lying"
            @severity = :warning
            @rule_tags = %i[SELF_EXPLAINING EXPLICIT]
          end

          def self.auto_build? = false

          def set_agent(agent)
            @agent = agent
            self
          end

          def check(code, path:)
            return [] unless path.end_with?(".rb") && @agent
            pairs = extract_pairs(code)
            return [] if pairs.empty?
            response = @agent.ask(build_prompt(pairs, path), operation: :scan_comment_drift).to_s
            parse_findings(response, pairs)
          rescue StandardError => e
            # An unreachable or misbehaving agent must not read as "no drift".
            Master::Ground::Swallow.log(e, context: "CommentDriftRule", severity: :load_bearing, path:)
            []
          end

          private

          def extract_pairs(code)
            lines = code.lines
            pairs = []
            i = 0
            while i < lines.size && pairs.size < MAX_PAIRS_PER_FILE
              comment_start = i
              while i < lines.size && lines[i] =~ /\A\s*#/
                i += 1
              end
              comment_lines = lines[comment_start...i]
              if comment_lines.any? && i < lines.size && lines[i] =~ /\A\s*def\s/
                comment_text = comment_lines.map { |l| l.strip.delete_prefix("#").strip }.join(" ")
                body = lines[i, BODY_SNIPPET].join
                pairs << { line: comment_start + 1, comment: comment_text, body: } unless comment_text.empty?
              end
              i += 1
            end
            pairs
          end

          def format_pair(p, idx)
            "[#{idx}] line #{p[:line]}\nCOMMENT: #{p[:comment]}\nCODE:\n#{p[:body]}"
          end

          def build_prompt(pairs, path)
            numbered = pairs.each_with_index.map { |p, idx| format_pair(p, idx) }.join("\n---\n")
            <<~PROMPT
            Audit #{File.basename(path)} for comment drift. For each numbered pair,
            decide whether the comment accurately describes what the code does.
            List ONLY indices where the comment lies or contradicts the code.
            Format each violation: INDEX:short reason (one per line)
            If all pairs are accurate, respond with exactly: CLEAN

            #{numbered}
          PROMPT
          end

          def parse_findings(response, pairs)
            return [] if response.strip.upcase == "CLEAN"
            response.lines.filter_map do |line|
              match = line.strip.match(/\A(\d+):(.+)\z/)
              next unless match
              pair_index = match[1].to_i
              pair = pairs[pair_index]
              next unless pair
              finding(line: pair[:line], message: "comment drift — #{match[2].strip}")
            end
          end
        end
      end
    end
  end
end
