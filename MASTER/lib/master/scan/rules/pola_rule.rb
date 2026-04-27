# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # PolaRule — Principle of Least Astonishment.
      # Code should behave as its name implies with no hidden side-effects.
      # Flags: boolean positional params, double negation, predicate methods
      # that mutate state, and negative boolean attribute names.
      class PolaRule < Rule
        # def call(file, true) — boolean positional default is opaque at call site
        BOOL_POSITIONAL = /def\s+\w+\([^)]*,\s*(true|false)\s*[,)]/.freeze
        # unless !condition (double negation)
        DOUBLE_NEG      = /\bunless\s+!/.freeze
        # Negative boolean attribute names
        NEG_BOOL_ATTR   = /\battr_\w+\s+:(?:not_|no_|without_|disabled?_|skip_)\w+/.freeze

        def initialize
          super
          @id          = "pola"
          @description = "Principle of Least Astonishment — surprising names, contracts, or side-effects"
          @severity    = :warning
          @axiom_tags  = [:EXPLICIT]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")

          findings        = []
          in_predicate    = false
          pred_line       = 0
          depth           = 0

          code.each_line.with_index(1) do |line, num|
            findings << finding(line: num, message: "boolean positional default — use keyword arg (def method(flag: false)) to name intent at call site") if line.match?(BOOL_POSITIONAL)
            findings << finding(line: num, message: "double negation (unless !x) — use positive form (if x)") if line.match?(DOUBLE_NEG)
            findings << finding(line: num,
              message: "negative attribute name — name what it IS, not what it ISN'T") if line.match?(NEG_BOOL_ATTR)

            if line.match?(/^\s+def\s+\w+\?/)
              in_predicate = true
              pred_line    = num
              depth        = 1
            elsif in_predicate
              depth += line.scan(/\bdo\b|\bbegin\b|\bif\b|\bcase\b|\bdef\b/).size
              depth -= line.scan(/\bend\b/).size
              if depth <= 0
                in_predicate = false
              elsif line.match?(/(@\w+\s*=(?!=)|\.save[!\s]|\.update[!\s]|File\.write)/)
                findings << finding(line: pred_line,
                  message: "predicate method (?) mutates state — predicates must only query, never mutate (POLA)")
                in_predicate = false
              end
            end
          end

          findings
        end
      end
    end
  end
end
