# frozen_string_literal: true

module Master
  module Voice
    class Renderer
      # Text transformation/formatting helpers — separate from Renderer's
      # own render/output-guard responsibility.
      module TextFormatting
        def format_error(message) = render(message, mode: :error)
        def format_dmesg(line) = @p.dim(line.to_s)

        def beautify(text)
          text
            .gsub(/"([^"]*?)"/) { "“#{Regexp.last_match(1)}”" }
            .gsub(/\s--\s/, " — ")
            .gsub(/(\d)-(\d)/, "\\1–\\2")
            .gsub("...", "…")
        end
      end
    end
  end
end
