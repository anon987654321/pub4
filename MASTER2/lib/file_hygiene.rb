# frozen_string_literal: true

module MASTER
  # FileHygiene - Clean up file formatting issues
  module FileHygiene
    extend self

    def clean(content)
      content = strip_bom(content)
      content = normalize_line_endings(content)
      content = strip_trailing_whitespace(content)
      content = ensure_final_newline(content)
      content
    end

    def clean_file(path)
      original = File.read(path)
      cleaned = clean(original)

      if original != cleaned
        Undo.track_edit(path, original) if defined?(Undo)
        File.write(path, cleaned)
        true
      else
        false
      end
    end

    def analyze(content)
      issues = []

      issues << :bom if has_bom?(content)
      issues << :crlf if has_crlf?(content)
      issues << :trailing_whitespace if has_trailing_whitespace?(content)
      issues << :no_final_newline unless ends_with_newline?(content)
      issues << :tabs if has_tabs?(content)

      issues
    end

    private

    def strip_bom(content)
      content.sub(/\A\xEF\xBB\xBF/, '')
    end

    def normalize_line_endings(content)
      content.gsub(/\r\n?/, "\n")
    end

    def strip_trailing_whitespace(content)
      content.gsub(/[ \t]+$/, '')
    end

    def ensure_final_newline(content)
      content.end_with?("\n") ? content : "#{content}\n"
    end

    def has_bom?(content)
      content.start_with?("\xEF\xBB\xBF")
    end

    def has_crlf?(content)
      content.include?("\r\n")
    end

    def has_trailing_whitespace?(content)
      content.match?(/[ \t]+$/)
    end

    def ends_with_newline?(content)
      content.end_with?("\n")
    end

    def has_tabs?(content)
      content.include?("\t")
    end
  end
end
