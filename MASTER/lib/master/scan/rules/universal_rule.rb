# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # UniversalRule — cross-language axiom enforcement.
      # All rules apply to all file types; vertical-spacing checks skip HTML/ERB
      # since blank lines affect markup output.
      class UniversalRule < Rule
        BLANK_FLOOD     = /\n{4,}/.freeze
        BOX_CHARS   = [0x256D,0x256E,0x2570,0x256F,0x2502,0x2500,0x250C,0x2510,0x2514,0x2518,
                       0x251C,0x2524,0x252C,0x2534,0x253C,0x2550,0x2551,0x2554,0x2557,0x255A,0x255D]
                       .map { |cp| cp.chr(Encoding::UTF_8) }.join.freeze
        BOX_DRAWING = Regexp.new("[#{Regexp.escape(BOX_CHARS)}]|={4,}|-{4,}").freeze
        OPAQUE_NAMES    = /\b(tmp|temp|val|ret|obj|str|arr|buf)\b\s*=/.freeze
        DEAD_AFTER_STOP = /\b(return|exit|raise|throw)\b.+\n\s*\S/.freeze
        STALE_COMMENT   = /^\s*#\s*(TODO|FIXME|HACK|REVIEW|NOTE):\s*$/i.freeze

        CHECKS = [
          { pattern: BLANK_FLOOD,     message: "more than 3 consecutive blank lines — use single blank between sections",       fix: "collapse to one blank line" },
          { pattern: BOX_DRAWING,     message: "box-drawing chars or separator lines — use whitespace as layout tool",          fix: "delete separators" },
          { pattern: OPAQUE_NAMES,    message: "generic variable name — use a domain-specific name",                            fix: nil },
          { pattern: STALE_COMMENT,   message: "empty TODO/FIXME marker — fill it or delete it",                               fix: "delete marker" },
        ].freeze

        def initialize
          super
          @id          = "universal"
          @description = "Cross-language axiom checks"
          @severity    = :info
          @auto_fix    = true
          @axiom_tags  = %i[SQUINT_TEST TYPOGRAPHY_DISCIPLINE MEANINGFUL_NAMES WHITESPACE_PUNCTUATION]
        end

        def check(code, path:)
          findings = []
          CHECKS.each do |check|
            code.each_line.with_index(1) do |line, number|
              findings << finding(line: number, message: check[:message], fix: check[:fix]) if line.match?(check[:pattern])
            end
          end
          check_dead_code(code, findings)
          check_dense_methods(code, findings)
          findings
        end

        private

        def check_dead_code(code, findings)
          code.each_line.with_index(1).each_cons(2) do |(line_a, number_a), (line_b, _)|
            next unless line_a.match?(DEAD_AFTER_STOP) && line_b.match?(/\S/)
            findings << finding(line: number_a, message: "dead code after #{line_a.strip.split.first} — remove unreachable lines", fix: "delete unreachable lines")
          end
        end

        def check_dense_methods(code, findings)
          code.each_line.with_index(1).each_cons(2) do |(line_a, number_a), (line_b, _)|
            stripped_a = line_a.strip
            stripped_b = line_b.strip
            next unless stripped_a == "end" && stripped_b.start_with?("def ")
            findings << finding(line: number_a, message: "no blank line between method definitions — add vertical spacing", fix: "insert blank line")
          end
        end
      end
    end
  end
end
