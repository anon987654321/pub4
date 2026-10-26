# frozen_string_literal: true

module Master
  module Fix
    # patch(1) reads unequal context as position, so a model's hunk that opened on
    # its "-" lines was refused mid-file (2026-10-26). Each hunk is rebuilt where
    # its old lines sit in the source, nearest the line the model named, with
    # equal context from the source; one the source does not hold stays as written.
    module HunkAnchor

      CONTEXT = 3
      HEADER = /\A@@ -(\d+),\d+ \+\d+,\d+ @@/

      module_function

      def anchor(diff_text, original)
        source = original.lines.map(&:chomp)
        out = []
        delta = 0
        each_part(diff_text.lines.map(&:chomp)) do |kind, lines|
          next out.concat(lines) unless kind == :hunk

          rebuilt = rebuild(lines, source:, delta:)
          delta += rebuilt.count { |line| line.start_with?("+") } - rebuilt.count { |line| line.start_with?("-") }
          out.concat(rebuilt)
        end
        "#{out.join("\n")}\n"
      end

      # Yields [:hunk, header + body] or [:text, lines] in order.
      def each_part(lines)
        hunk = nil
        lines.each do |line|
          if line.match?(HEADER)
            yield(:hunk, hunk) if hunk

            hunk = [line]
          elsif hunk && line.start_with?(" ", "-", "+", "\\")
            hunk << line
          else
            yield(:hunk, hunk) if hunk

            hunk = nil
            yield(:text, [line])
          end
        end
        yield(:hunk, hunk) if hunk
      end

      def rebuild(hunk, source:, delta:)
        body = hunk.drop(1)
        old_text = old_side(body)
        at = locate(old_text, source:, near: hunk.first[HEADER, 1].to_i - 1)
        return hunk unless at

        before, after = padding(body, source:, from: at, to: at + old_text.size)
        header(before + body + after, start: at - before.size + 1, delta:)
      end

      # Source lines to add before and after so both sides carry equal context.
      def padding(body, source:, from:, to:)
        lead = context_size(body)
        trail = context_size(body.reverse)
        target = [lead, trail, CONTEXT].max
        before = source[[from - (target - lead), 0].max...from]
        after = source[to, target - trail].to_a
        [before, after].map { |lines| lines.map { |line| " #{line}" } }
      end

      def header(lines, start:, delta:)
        old = lines.count { |line| line.start_with?(" ", "-") }
        new = lines.count { |line| line.start_with?(" ", "+") }
        ["@@ -#{start},#{old} +#{start + delta},#{new} @@", *lines]
      end

      # The index where old_text starts in source, nearest the named line, or nil.
      def locate(old_text, source:, near:)
        return if old_text.empty?

        hits = (0..(source.size - old_text.size)).select { |index| source[index, old_text.size] == old_text }
        hits.min_by { |index| (index - near).abs }
      end

      def old_side(body) = body.select { |line| line.start_with?(" ", "-") }.map { |line| line[1..] }

      def context_size(lines) = lines.take_while { |line| line.start_with?(" ") }.size
    end
  end
end
