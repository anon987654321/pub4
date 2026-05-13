# frozen_string_literal: true

module Master
  module Judge
  module Scan
    module Rules
      # Comments above method defs that no longer describe what the code does.
      # Lexical pass extracts (comment, method_body) pairs; LLM judges drift in one
      # batched call per file. Pairs with the "reassess on touch" directive: lying
      # comments are factual bugs, not style noise.
      class CommentDriftRule < Rule
        MAX_PAIRS_PER_FILE = 8
        BODY_SNIPPET       = 20  # lines of method body sent to LLM

        def initialize(agent: nil)
          super()
          @agent       = agent
          @id          = "comment_drift"
          @description = "Comment claim doesn't match method body — comment is lying"
          @severity    = :warning
          @rule_tags  = %i[SELF_EXPLAINING EXPLICIT]
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
        rescue StandardError
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
              pairs << { line: comment_start + 1, comment: comment_text, body: body } unless comment_text.empty?
            end
            i += 1
          end
          pairs
        end

        def build_prompt(pairs, path)
          numbered = pairs.each_with_index.map do |p, idx|
            "[#{idx}] line #{p[:line]}\nCOMMENT: #{p[:comment]}\nCODE:\n#{p[:body]}"
          end.join("\n---\n")
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
            idx = match[1].to_i
            pair = pairs[idx]
            next unless pair
            finding(line: pair[:line], message: "comment drift — #{match[2].strip}")
          end
        end
      end
    end
  end
  end
end
