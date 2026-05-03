# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # UniversalRule — cross-language axiom enforcement.
      # Applies to every file type regardless of extension.
      # Rules: SQUINT_TEST, TYPOGRAPHY_DISCIPLINE, MEANINGFUL_NAMES,
      #        DEAD_CODE, WHITESPACE_PUNCTUATION.
      class UniversalRule < Rule
        BLANK_FLOOD      = /\n{4,}/.freeze
        BOX_DRAWING      = /[╭╮╰╯│─┌┐└┘├┤┬┴┼═║╔╗╚╝]|={4,}|-{4,}/.freeze
        OPAQUE_NAMES     = /\b(tmp|temp|data|result|val|ret|obj|str|arr|buf)\b\s*=/.freeze
        DEAD_AFTER_STOP  = /\b(return|exit|raise|throw)\b.+\n\s*\S/.freeze
        STALE_COMMENT    = /^\s*#\s*(TODO|FIXME|HACK|REVIEW|NOTE):\s*$/i.freeze

        CHECKS = [
          { id: "SQUINT_TEST",           pattern: BLANK_FLOOD,     message: "more than 3 consecutive blank lines — use single blank between sections" },
          { id: "TYPOGRAPHY_DISCIPLINE", pattern: BOX_DRAWING,     message: "box-drawing chars or separator lines — use whitespace as layout tool" },
          { id: "MEANINGFUL_NAMES",      pattern: OPAQUE_NAMES,    message: "generic variable name — use a domain-specific name" },
          { id: "STALE_COMMENT",         pattern: STALE_COMMENT,   message: "empty TODO/FIXME marker — fill it or delete it" },
        ].freeze

        def initialize
          super
          @id          = "universal"
          @description = "Cross-language axiom checks (all file types)"
          @severity    = :info
          @axiom_tags  = %i[SQUINT_TEST TYPOGRAPHY_DISCIPLINE MEANINGFUL_NAMES BE_CONCISE]
        end

        def check(code, path:)
          return [] if language(path).nil?

          findings = []
          CHECKS.each do |chk|
            code.each_line.with_index(1) do |line, num|
              findings << finding(line: num, message: chk[:message]) if line.match?(chk[:pattern])
            end
          end

          check_dead_code(code, findings)
          findings
        end

        private

        def check_dead_code(code, findings)
          code.each_line.with_index(1).each_cons(2) do |(line_a, num_a), (line_b, _num_b)|
            next unless line_a.match?(DEAD_AFTER_STOP) && line_b.match?(/\S/)
            findings << finding(line: num_a, message: "dead code after #{line_a.strip.split.first} — remove unreachable lines")
          end
        end
      end
    end
  end
end
