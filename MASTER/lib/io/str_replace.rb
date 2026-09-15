# frozen_string_literal: true

module Master
  module Io
    class StrReplace
      include Base
      TIER = :guarded
      NAME = "str_replace".freeze
      DESCRIPTION = "Replace unique string in a file. Fails if pattern matches 0 or 2+ times.".freeze

      # A model copies old_string out of a read and loses what the read did not
      # show: trailing spaces, a tab turned to spaces, a curly quote typed
      # straight. Exact matching stays first and is the only match allowed inside
      # a line. These passes compare whole lines, loosest last, and a pass that
      # finds more than one window refuses rather than choosing.
      TOLERANT_PASSES = {
        rstrip: ->(line) { line.rstrip },
        strip: ->(line) { line.strip },
        punctuation: ->(line) { line.strip.tr("\u2018\u2019\u201C\u201D\u2013\u2014\u00A0", "''\"\"-- ").squeeze(" ") },
      }.freeze

      def initialize(root:, undo:, governor:, event_bus: nil, diff_stager: nil, ground_truth: nil)
        @root, @undo, @governor, @bus, @diff_stager, @ground_truth =
          File.realpath(root), undo, governor, event_bus, diff_stager, ground_truth
      end

      def call(path:, old_string:, new_string:)
        safely do
          resolved = resolve(path)
          next resolved if resolved.err?

          full = resolved.value!
          next Result.err("not found: #{path}", category: :validation) unless File.exist?(full)

          content = File.read(full)
          updated = resolve_updated_content(content, old_string, new_string, path)
          next updated if updated.is_a?(Result::Err)

          perm = permit(path)
          next perm if perm.err?

          commit_write(full, updated, path:)
        end
      end

      def resolve_updated_content(content, old_string, new_string, path)
        anchor = Hashline.parse_anchor(old_string)
        return anchored_content(content, anchor, new_string, path) if anchor

        count = content.scan(old_string).size
        # The block form: a string replacement reads \0, \1 and \& as
        # backreferences, so replacement Ruby or regex source came back rewritten.
        return content.sub(old_string) { new_string } if count == 1
        return Result.err("str_replace: pattern matches #{count} times in #{path} (must be unique)", category: :validation) if count > 1

        tolerant_content(content, old_string, new_string, path)
      end

      private

      def anchored_content(content, anchor, new_string, path)
        line = content.lines[anchor[:line] - 1]
        return Result.err("hashline: line #{anchor[:line]} missing in #{path}", category: :validation) unless line

        replaced = Hashline.replace_line(content, line_no: anchor[:line], id: anchor[:id], new_line: new_string)
        return replaced if replaced.err?

        replaced.value!
      end

      def tolerant_content(content, old_string, new_string, path)
        wanted = old_string.lines.map(&:chomp)
        not_found = Result.err("str_replace: pattern not found in #{path}", category: :validation)
        return not_found if wanted.all? { |line| line.strip.empty? }

        lines = content.lines
        TOLERANT_PASSES.each do |pass, normalize|
          starts = window_starts(lines, wanted, normalize)
          next if starts.empty?
          return ambiguous(path, starts.size, pass) if starts.size > 1

          @bus&.publish("tool:healed", tool: NAME, path:, pass:)
          return splice(lines, starts.first, wanted.size, new_string)
        end
        not_found
      end

      def ambiguous(path, count, pass)
        Result.err("str_replace: pattern matches #{count} places in #{path} ignoring #{pass} (must be unique)", category: :validation)
      end

      def window_starts(lines, wanted, normalize)
        target = wanted.map(&normalize)
        (0..(lines.size - wanted.size)).select do |start|
          lines[start, wanted.size].map { |line| normalize.call(line.chomp) } == target
        end
      end

      # The replaced window keeps its own line ending, so a match on a last line
      # without a newline does not gain one, and an empty replacement deletes.
      def splice(lines, start, length, new_string)
        ending = lines[start + length - 1].end_with?("\n") ? "\n" : ""
        replacement = new_string.empty? ? "" : "#{new_string.chomp}#{ending}"
        (lines[0, start] + [replacement] + lines[(start + length)..]).join
      end
    end
  end
end
