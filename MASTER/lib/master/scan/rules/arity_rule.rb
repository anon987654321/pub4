# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # Too many constructor args signal a god object; callers can't reason about what matters.
      # Reads max_params from rules.yml so the threshold stays in one place.
      class ArityRule < Rule
        DEFAULT_MAX = 3

        def initialize
          super
          @max_params  = Master::Axioms.new.thresholds.dig("method", "max_params") || DEFAULT_MAX
          @id          = "arity"
          @description = "initialize with > #{@max_params} args — extract a context struct or config object"
          @severity    = :warning
          @axiom_tags  = %i[DECOUPLE ONE_JOB]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          findings = []
          lines = code.lines
          i = 0
          while i < lines.size
            line = lines[i]
            if line.match?(/^\s*def\s+initialize\s*\(/)
              sig, end_idx = collect_signature(lines, i)
              count = count_params(sig)
              findings << finding(line: i + 1,
                message: "initialize takes #{count} args (max #{@max_params}) — extract AgentContext or Config struct") if count > @max_params
              i = end_idx + 1
            else
              i += 1
            end
          end
          findings
        end

        private

        def collect_signature(lines, start)
          sig = +""
          depth = 0
          i = start
          while i < lines.size
            sig << lines[i]
            depth += lines[i].count("(") - lines[i].count(")")
            break if depth <= 0
            i += 1
          end
          [sig, i]
        end

        def count_params(sig)
          inner = sig.match(/def\s+initialize\s*\((.+)\)/m)
          return 0 unless inner
          content = inner[1].strip
          return 0 if content.empty?
          depth = 0
          count = 1
          content.each_char do |c|
            case c
            when "(", "[", "{" then depth += 1
            when ")", "]", "}" then depth -= 1
            when "," then count += 1 if depth.zero?
            end
          end
          count
        end
      end
    end
  end
end
