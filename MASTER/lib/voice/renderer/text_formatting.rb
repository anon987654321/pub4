# frozen_string_literal: true

module Master
  module Voice
    class Renderer
      # Text transformation/formatting helpers — separate from Renderer's
      # own render/output-guard responsibility.
      module TextFormatting
        # Bringhurst's measure for a terminal: prose wraps near 66 to 72 columns.
        MEASURE = 72
        LIST_LEAD = /\A\s*(?:[-*•]\s+|\d+[.)]\s+)?/

        # Wraps prose to the measure at a space, never inside a word, with a
        # list item's continuation hung under its text. Code fences, indented
        # lines, table rows and key=value lines keep their shape, because their
        # columns mean something.
        def measure(text, width: MEASURE)
          fenced = false
          text.to_s.lines.map do |line|
            fence = line.lstrip.start_with?("```")
            fenced = !fenced if fence
            fence || fenced || !prose_line?(line, width) ? line : wrap_line(line, width)
          end.join
        end

        def format_dmesg(line) = @p.dim(line.to_s)

        # Only a standalone numeric range earns an en dash. Firing on any
        # digit-hyphen-digit rewrote identifiers and dates too: model IDs
        # printed as claude-opus-4–8 and dates as 2026–08–02.
        def beautify(text)
          curl_quotes(text)
            .gsub(/\s--\s/, " — ")
            .gsub(/(?<![\w-])(\d+)-(\d+)(?![\w-])/, "\\1–\\2")
            .gsub("...", "…")
        end

        private

        # A quoted string on a record line is a value, and curling it changes the
        # value: a repair preview printed {“FEW_ARGUMENTS” => 28}, which is no
        # longer the hash it came from and no longer pastes back into anything.
        # The test is the one prose_line? already uses for the same reason — a
        # line carrying an `=` is a record, and its columns mean something.
        def curl_quotes(text)
          lines = text.lines.map do |line|
            next line if line.include?("=")

            line.gsub(/"([^"]*?)"/) { "“#{Regexp.last_match(1)}”" }
          end
          lines.join
        end

        # A sentence, not a record: long, a dozen words or more, and mostly
        # words rather than numbers, paths and identifiers.
        def prose_line?(line, width)
          body = line.chomp
          return false if body.length <= width || body.match?(/\A(?: {4}|\t|\|)/) || body.include?("=")

          words = body.split
          words.size >= 12 && words.count { |word| word.match?(%r{[\d_/]}) } * 4 <= words.size
        end

        def wrap_line(line, width)
          lead = line[LIST_LEAD]
          rows = [lead.dup]
          line.chomp.delete_prefix(lead).split(/ +/).each do |word|
            if rows.last.length > lead.length && rows.last.length + 1 + word.length > width
              rows << (" " * lead.length) + word
            else
              rows.last << (rows.last.length > lead.length ? " " : "") << word
            end
          end
          rows.join("\n") + (line.end_with?("\n") ? "\n" : "")
        end
      end
    end
  end
end
