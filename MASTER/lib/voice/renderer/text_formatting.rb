# frozen_string_literal: true

module Master
  module Voice
    class Renderer
      # Text transformation/formatting helpers — separate from Renderer's
      # own render/output-guard responsibility.
      module TextFormatting
        # Preserve authored line and paragraph boundaries. Terminals soft-wrap at
        # the viewport edge; inserting newline characters here corrupts copied
        # text, streamed paragraphs and transcripts. width remains accepted for
        # callers that used the old signature.
        MEASURE = 72

        def measure(text, **_options)
          text.to_s
        end

        # Render common Markdown without changing authored line lengths or
        # paragraph boundaries. Fences, tables and record lines keep their shape.
        def terminal_markdown(text, width: MEASURE)
          # The CLI's presentation path must retain the same evidence guard as
          # Renderer#render; Markdown cleanup is not a second trust boundary.
          source = output_guard.sanitize(text.to_s, context: :routine)
          rows = []
          fenced = false

          source.lines.each do |line|
            body = line.chomp
            if body.lstrip.start_with?("```")
              fenced = !fenced
              rows << "" if rows.any? && !rows.last.empty?
              next
            end

            if fenced
              rows << (body.empty? ? "" : "    #{body}")
              next
            end

            next rows << "" if body.empty?

            if (heading = body.match(/\A\s{0,3}\#{1,6}\s+(.+)\z/))
              rows.concat(measure(heading[1], width:).lines(chomp: true).map { |row| markdown_emphasis(row) })
              next
            end

            if body.match?(/\A\s{0,3}(?:---+|\*\*\*+|___+)\s*\z/)
              rows << "----"
              next
            end

            body = body.sub(/\A\s{0,3}>\s?/, "  ")
            body = body.sub(/\A\s{0,3}\*\s+/, "- ")
            body = body.gsub(/\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/) do
              label = Regexp.last_match(1)
              url = Regexp.last_match(2)
              label == url ? url : "#{label} (#{url})"
            end
            body = body.gsub(/\*\*(.+?)\*\*/) { Regexp.last_match(1) }
            body = body.gsub(/(?<!\*)\*([^*\n]+)\*(?!\*)/) { Regexp.last_match(1) }
            body = body.gsub(/__([^_\n]+)__/) { Regexp.last_match(1) }
            body = body.gsub(/`([^`\n]+)`/) { Regexp.last_match(1) }
            rows.concat(measure(beautify(body), width:).lines(chomp: true))
          end

          rows.join("\n") + (source.end_with?("\n") ? "\n" : "")
        end

        def format_dmesg(line) = @p.dim(line.to_s)

        # The terminal prints ASCII (operator, 2026-11-06), so prose leaves
        # here as straight quotes, "-" and "...":
        # a double hyphen between words becomes the one hyphen, and the
        # double space after a sentence closes to one. Record lines (a "=" or
        # a URL) carry data and keep their spacing as written.
        def beautify(text)
          text.lines.map do |line|
            next line if line.include?("=") || line.include?("://")

            line.gsub(/\s--\s/, " - ").gsub(/([.!?])  +(?=\S)/, "\\1 ")
          end.join
        end

        private

        def markdown_emphasis(text)
          return text unless $stdout.tty?

          @p.bold(text)
        rescue StandardError
          text
        end
      end
    end
  end
end
