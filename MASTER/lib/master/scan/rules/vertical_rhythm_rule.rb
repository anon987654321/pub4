# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # House rhythm: exactly one blank line between method defs, none inside a method,
      # exactly two blank lines between top-level class/module definitions.
      class VerticalRhythmRule < Rule
        def initialize
          super
          @id          = "vertical_rhythm"
          @description = "Inter-method blank-line spacing deviates from house rhythm"
          @severity    = :info
          @axiom_tags  = %i[POLA_PRINCIPLE IMPORTANCE_ORDER]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          lines = code.lines
          findings = []
          lines.each_with_index do |line, i|
            next unless line =~ /\A\s*def\s/
            blanks = count_blanks_above(lines, i)
            next if i.zero? || blanks == 1 || prev_meaningful_is_class_open?(lines, i)
            findings << finding(line: i + 1, message: "expected 1 blank line above def, found #{blanks}")
          end
          findings
        end

        private

        def count_blanks_above(lines, idx)
          n = 0
          j = idx - 1
          while j >= 0 && lines[j].strip.empty?
            n += 1
            j -= 1
          end
          n
        end

        def prev_meaningful_is_class_open?(lines, idx)
          j = idx - 1
          j -= 1 while j >= 0 && lines[j].strip.empty?
          return false if j < 0
          lines[j] =~ /\A\s*(?:class|module|private|protected|public)\b/
        end
      end
    end
  end
end
