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
          lines    = code.lines
          index    = 0
          while index < lines.size
            line = lines[index]
            if line.match?(/^\s*def\s+initialize\s*\(/)
              signature, end_index = collect_signature(lines, index)
              param_count = count_params(signature)
              findings << finding(line: index + 1,
                message: "initialize takes #{param_count} args (max #{@max_params}) — extract AgentContext or Config struct") if param_count > @max_params
              index = end_index + 1
            else
              index += 1
            end
          end
          findings
        end

        private

        def collect_signature(lines, start)
          signature = +""
          depth     = 0
          current   = start
          while current < lines.size
            signature << lines[current]
            depth += lines[current].count("(") - lines[current].count(")")
            break if depth <= 0
            current += 1
          end
          [signature, current]
        end

        def count_params(signature)
          inner = signature.match(/def\s+initialize\s*\((.+)\)/m)
          return 0 unless inner
          content = inner[1].strip
          return 0 if content.empty?
          depth = 0
          count = 1
          content.each_char do |char|
            case char
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
