# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # Every Ruby file opens the same way: frozen-string-literal, blank, requires
      # (alphabetized), blank, module/class. Inside each class: CONSTANTS, attr_*,
      # initialize, public methods, blank line + `private`, private methods.
      class FileLayoutRule < Rule
        FROZEN_RE = /\A#\s*frozen_string_literal:\s*true\s*\z/.freeze
        REQUIRE_RE = /\Arequire(?:_relative)?\s+/.freeze
        DEF_RE = /\A\s*(?:def\s|private\b|protected\b|public\b|attr_\w+|[A-Z][A-Z0-9_]*\s*=)/.freeze

        def initialize
          super
          @id          = "file_layout"
          @description = "File header or class member order deviates from house layout"
          @severity    = :warning
          @axiom_tags  = %i[IMPORTANCE_ORDER POLA_PRINCIPLE]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          findings = []
          findings.concat(header_findings(code))
          findings.concat(require_order_findings(code))
          findings.concat(class_member_findings(code))
          findings
        end

        private

        def header_findings(code)
          first = code.lines.first&.rstrip
          return [finding(line: 1, 
message: "missing `# frozen_string_literal: true` magic comment")] unless first&.match?(FROZEN_RE)
          []
        end

        def require_order_findings(code)
          requires = code.lines.each_with_index.select { |l, _| l.match?(REQUIRE_RE) }
          return [] if requires.size < 2
          names = requires.map { |l, _| l[/\Arequire(?:_relative)?\s+["']([^"']+)/, 1] }.compact
          return [] if names == names.sort
          [finding(line: requires.first[1] + 1, message: "require lines should be alphabetized")]
        end

        def class_member_findings(code)
          private_idx = code.lines.each_with_index.find { |l, _| l.strip == "private" }
          return [] unless private_idx
          line_num = private_idx[1] + 1
          before = code.lines[0...private_idx[1]]
          after  = code.lines[(private_idx[1] + 1)..]
          findings = []
          findings << finding(line: line_num, 
message: "`private` should sit on its own line with blank line above") unless blank_above?(
code.lines, private_idx[1])
          findings << finding(line: line_num, 
message: "method order: definitions before `private` should not include helpers (move below)") if mixed_section?(before)
          findings << finding(line: line_num, 
message: "constants/attr_* must precede first def") if late_constants?(before)
          findings
        end

        def blank_above?(lines, idx)
          idx.zero? || lines[idx - 1].strip.empty?
        end

        def mixed_section?(_lines)
          false
        end

        def late_constants?(lines)
          first_def = lines.index { |l| l =~ /\A\s*def\s/ }
          return false unless first_def
          lines[(first_def + 1)..].any? { |l| l =~ /\A\s*[A-Z][A-Z0-9_]*\s*=/ }
        end
      end
    end
  end
end
