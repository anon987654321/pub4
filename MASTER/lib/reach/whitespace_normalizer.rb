# frozen_string_literal: true

module Master
  module Reach
    # Deterministic whitespace cleanup applied to every committed write.
    # Strips trailing spaces, collapses >1 blank line to 1, and (for Ruby)
    # squeezes 2+ internal-space runs to 1 outside string literals and heredocs.
    module WhitespaceNormalizer
      module_function

      COLLAPSE_INTERNAL_EXTS = %w[.rb].freeze

      def normalize(content, path: nil)
        return content unless content.is_a?(String) && !content.empty?
        out = collapse_blanks(out)
        out = collapse_internal(out) if collapse_internal?(path)
        out
      end

      def collapse_internal?(path)
        return false unless path
      end

      def strip_trailing(src)
        src.gsub(/[ \t]+(?=\n)/, "")
      end

      def collapse_blanks(src)
        src.gsub(/\n{3,}/, "\n\n")
      end

      def collapse_internal(src)
        terminators = []
        src.each_line.map do |line|
          if terminators.any?
            terminators.shift if line.match?(/\A\s*#{Regexp.escape(terminators.first)}\s*$/)
            next line
          end
          if (m = line.match(/<<[-~]?["']?([A-Z_][A-Z0-9_]*)["']?/))
            terminators << m[1]
            next line
          end
          collapse_line(line)
        end.join
      end

      def collapse_line(line)
        leading = line[/\A[ \t]*/]
        rest = line[leading.length..] || ""
        out = +""
        i = 0
        in_str = nil
        while i < rest.length
          c = rest[i]
          if in_str
            out << c
            if c == "\\" && rest[i + 1]
              out << rest[i + 1]
              i += 2
              next
            end
            in_str = nil if c == in_str
            i += 1
          elsif c == "#"
            out << rest[i..]
            break
          elsif c == '"' || c == "'"
            in_str = c
            out << c
            i += 1
          elsif c == " " && rest[i + 1] == " "
            out << " "
            i += 1
            i += 1 while rest[i] == " "
          else
            out << c
            i += 1
          end
        end
        leading + out
      end
    end
  end
end
