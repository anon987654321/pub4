# frozen_string_literal: true

require "prism"

module Master
  module Fix
    module Scan
      class AstFixer
        # VERTICAL_BREATH wants a blank line in any run of ten lines. This puts one between two sibling
        # statements, so it never lands inside a string, a heredoc or a call; a run with no such boundary
        # stays as it is. It adds whitespace only.
        module VerticalBreath
          DENSE_RUN = 10

          private

          def add_vertical_breath(src)
            parsed = Prism.parse(src)
            return src if parsed.failure?

            lines = src.lines
            breaks = breath_points(lines, statement_boundaries(parsed.value, src))
            return src if breaks.empty?

            @transforms << :vertical_breath
            breaks.sort.reverse_each { |after| lines.insert(after, "\n") }
            lines.join
          end

          # The bodies a blank line may divide: a file, a class or module, a method, a block. A branch of a
          # case, an if or a rescue is one thought; splitting its two lines put blank lines inside `when`.
          BREATHING_BODIES = [
            Prism::ProgramNode, Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode,
            Prism::DefNode, Prism::BlockNode, Prism::LambdaNode, Prism::BeginNode
          ].freeze

          # Line numbers L such that a blank line may go between line L and line L + 1: the last line of a
          # statement whose next sibling starts on a later line, in a breathing body, and not part of a
          # multi-line literal.
          def statement_boundaries(root, src)
            literal = literal_lines(src)
            boundaries = Set.new

            stack = [[root, nil]]
            until stack.empty?
              node, parent = stack.pop
              stack.concat(node.compact_child_nodes.map { |child| [child, node] })
              next unless node.is_a?(Prism::StatementsNode) && BREATHING_BODIES.any? { |kind| parent.is_a?(kind) }

              node.body.each_cons(2) do |current, following|
                line = current.location.end_line
                next if following.location.start_line <= line || literal.include?(line) || literal.include?(line + 1)

                boundaries << line
              end
            end
            boundaries
          end

          # The lines after which a blank goes: each dense run is split at the boundary nearest its middle, and
          # each half is split again while it is still dense.
          def breath_points(lines, boundaries)
            dense_runs(lines).flat_map { |first, last| split_dense(first:, last:, boundaries:) }
          end

          # [first, last] line numbers (1-based) of every run of DENSE_RUN or more lines with no blank line.
          def dense_runs(lines)
            runs = []
            start = nil
            lines.each_with_index do |line, index|
              if line.strip.empty?
                runs << [start, index] if start && index - start + 1 >= DENSE_RUN

                start = nil
              else
                start ||= index + 1
              end
            end
            runs << [start, lines.size] if start && lines.size - start + 1 >= DENSE_RUN
            runs
          end

          def split_dense(first:, last:, boundaries:)
            return [] if last - first + 1 < DENSE_RUN

            inside = boundaries.select { |line| line >= first && line < last }
            return [] if inside.empty?

            middle = (first + last) / 2.0
            at = inside.min_by { |line| (line - middle).abs }
            [at] + split_dense(first:, last: at, boundaries:) + split_dense(first: at + 1, last:, boundaries:)
          end
        end
      end
    end
  end
end
