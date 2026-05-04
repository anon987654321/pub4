# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class DeadAssignRule < Rule
        # Match: leading whitespace, lowercase lvar, single = (not ==, +=, -=, =~, =>)
        ASSIGN = /^\s+([a-z_][a-z0-9_]*)\s*=(?![>=~])/.freeze

        def initialize
          super
          @id          = "dead_assign"
          @description = "Local variable assigned but never read — remove or use it"
          @severity    = :warning
          @axiom_tags  = [:EXPLICIT]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          extract_methods(code).flat_map { |m| check_method(m) }
        end

        private

        def extract_methods(code)
          methods = []
          lines   = code.lines
          i       = 0
          while i < lines.size
            if lines[i].match?(/^\s*def \w/)
              start = i
              depth = 1
              i += 1
              while i < lines.size && depth > 0
                stripped = lines[i].strip
                depth += stripped.scan(/\b(?:def|do|begin|if|unless|case|class|module)\b/).size
                depth -= stripped.scan(/\bend\b/).size
                i += 1
              end
              methods << { lines: lines[start...i], start_line: start + 1 }
            else
              i += 1
            end
          end
          methods
        end

        def check_method(method)
          lines    = method[:lines]
          start    = method[:start_line]
          findings = []

          lines.each_with_index do |line, i|
            stripped = line.strip
            next if stripped.start_with?("#")
            m = line.match(ASSIGN)
            next unless m

            var = m[1]
            next if var.start_with?("_")               # intentionally unused
            next if %w[true false nil self].include?(var)

            rest = lines[(i + 1)..].join
            next if rest.match?(/\b#{Regexp.escape(var)}\b/)

            findings << finding(line: start + i, message: "#{var} is assigned but never read — remove or use it")
          end
          findings
        end
      end
    end
  end
end
