# frozen_string_literal: true

module Master
  module Voice
    class Renderer
      # Text transformation/formatting helpers — separate from Renderer's
      # own render/output-guard responsibility.
      module TextFormatting
        def format_error(message) = render(message, mode: :error)
        def format_dmesg(line) = @p.dim(line.to_s)

        # Only a standalone numeric range earns an en dash. Firing on any
        # digit-hyphen-digit rewrote identifiers and dates too: model IDs
        # printed as claude-opus-4–8 and dates as 2026–08–02.
        def beautify(text)
          text
            .gsub(/"([^"]*?)"/) { "“#{Regexp.last_match(1)}”" }
            .gsub(/\s--\s/, " — ")
            .gsub(/(?<![\w-])(\d+)-(\d+)(?![\w-])/, "\\1–\\2")
            .gsub("...", "…")
        end
      end
    end
  end
end
