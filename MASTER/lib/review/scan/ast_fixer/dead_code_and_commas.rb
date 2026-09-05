# frozen_string_literal: true

module Master
  module Review
    module Scan
      class AstFixer
        # Dead-code-after-unconditional-return removal and trailing-comma
        # insertion — both line-heuristic transforms that need to know which
        # lines sit inside multi-line string/heredoc/regexp literals, so they
        # share the literal_lines memoization and the small predicate helpers
        # below. Separate concern from AstFixer's own transform dispatch.
        module DeadCodeAndCommas
          private

          def remove_immediate_dead_code(src)
            protected_lines = literal_lines(src)
            lines = src.lines
            keep = []
            changed = false
            skip_next = false
            lines.each_with_index do |line, index|
              lineno = index + 1
              if skip_next && executable_line?(line) && !protected_lines.include?(lineno)
                changed = true
                skip_next = false
                next
              end
              keep << line
              next_line = lines[index + 1].to_s
              # A trailing backslash means the statement continues on the next
              # physical line — usually its guard: `return {...} \` + `if c`.
              # Deleting that "dead" line makes the return unconditional and
              # the file still parses, so nothing downstream notices. It broke
              # RadioChop's multiple-margin check in e7a48-era history, and
              # again on 2026-08-18, against the comment narrating the first
              # time.
              skip_next = !protected_lines.include?(lineno) && !protected_lines.include?(lineno + 1) &&
                !line.rstrip.end_with?("\\") &&
                unconditional_terminal?(line) && skippable_dead_line?(next_line) && !open_collection?(line)
            end
            @transforms << :dead_code if changed
            keep.join
          end

          # Line numbers (1-based) that sit inside a *multi-line* string, heredoc, command,
          # or regexp literal. Line-heuristic transforms must skip these — shell `exit`, a
          # Python `raise`, or a `}` inside a heredoc are data, not Ruby code. Single-line
          # literals don't span lines, so they never confuse the heuristics and stay eligible.
          LITERAL_NODES = [
            Prism::StringNode, Prism::InterpolatedStringNode,
            Prism::XStringNode, Prism::InterpolatedXStringNode,
            Prism::RegularExpressionNode, Prism::InterpolatedRegularExpressionNode,
          ].freeze

          # Memoized by source content: remove_immediate_dead_code and add_trailing_commas
          # both ask for the literal lines, and the source is usually unchanged between them,
          # so this saves a redundant full Prism parse per file on every autoloop cycle.
          def literal_lines(src)
            (@literal_lines ||= {})[src] ||= compute_literal_lines(src)
          end

          def compute_literal_lines(src)
            result = Prism.parse(src)
            return Set.new if result.failure?

            lines = Set.new
            stack = [result.value]
            until stack.empty?
              node = stack.pop
              next unless node
              loc = node.location
              if loc.start_line != loc.end_line && LITERAL_NODES.any? { |klass| node.is_a?(klass) }
                (loc.start_line..loc.end_line).each { |line| lines << line }
              end
              stack.concat(node.compact_child_nodes) if node.respond_to?(:compact_child_nodes)
            end
            lines
          rescue StandardError
            Set.new
          end

          def open_collection?(line)
            counts = line.each_char.with_object(Hash.new(0)) { |ch, tally| tally[ch] += 1 if "(){}[]".include?(ch) }
            counts["("] > counts[")"] || counts["{"] > counts["}"] || counts["["] > counts["]"]
          end

          def unconditional_terminal?(line)
            stripped = line.strip
            return false unless stripped.match?(/\A(?:return|raise|exit|throw)\b/)
            return false if stripped.match?(/\b(?:if|unless)\s/)

            true
          end

          def skippable_dead_line?(line)
            stripped = line.strip
            return false if stripped.empty?
            return false if stripped.start_with?("#", "//")
            return false if stripped.match?(/\A(?:end|else|elsif|when|rescue|ensure)\b/)

            true
          end

          def executable_line?(line) = skippable_dead_line?(line)

          def add_trailing_commas(src)
            protected_lines = literal_lines(src)
            lines = src.lines
            changed = false
            (1...lines.length).each do |i|
              next if protected_lines.include?(i) || protected_lines.include?(i + 1)

              current = lines[i].strip
              previous = lines[i - 1]
              next unless current.match?(/^[\]}]/)
              next if block_close?(lines, i)
              next if percent_word_array_close?(lines, i)
              next if previous.rstrip.end_with?(",", "[", "{", "(")
              next unless previous.match?(/^\s*[^#\n]+/)

              lines[i - 1] = previous.rstrip + ",\n"
              changed = true
            end
            @transforms << :trailing_commas if changed
            lines.join
          end

          def block_close?(lines, close_index)
            depth = 0
            close_index.downto(0) do |index|
              line = lines[index]
              depth += line.count("}") - line.count("{")
              next unless depth.zero? && line.match?(/\{\s*\|/)

              return true
            end
            false
          end

          def percent_word_array_close?(lines, close_index)
            close_line = lines[close_index].strip
            return false unless close_line.start_with?("]")

            close_index.downto(0) do |index|
              return true if lines[index].match?(%r/%[iIwW]\[/)
              return false if lines[index].strip.start_with?("[", "{")
            end
            false
          end
        end
      end
    end
  end
end
