# frozen_string_literal: true

module Master
  # TextHygiene — deterministic pre-write normalization.
  # Ported from MASTER2. Strips BOM, zero-width chars, CRLF, trailing spaces.
  # Called by WriteFile and StrReplace tools before writing.
  module TextHygiene
    BINARY_EXTS = %w[.png .jpg .jpeg .gif .webp .pdf .zip .gz .tgz .mp3 .mp4 .mov .woff .woff2].freeze

    module_function

    def normalize(content, filename: nil, ensure_final_newline: true)
      return content unless content.is_a?(String)

      out = content.dup
      out.gsub!("\r\n", "\n")
      out.gsub!("\r", "\n")
      out.sub!(/\A\xEF\xBB\xBF/, "")
      out.gsub!(/[\u200B\u200C\u200D\uFEFF]/, "")
      out.gsub!(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/, "")
      out.gsub!(/[ \t]+$/, "")

      if ensure_final_newline && text_like?(filename) && !out.empty? && !out.end_with?("\n")
        out << "\n"
      end

      out
    end

    def text_like?(filename)
      return true if filename.nil?

      ext = File.extname(filename.to_s).downcase
      !BINARY_EXTS.include?(ext)
    end
  end
end
