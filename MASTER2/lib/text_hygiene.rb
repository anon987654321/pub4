# frozen_string_literal: true

module MASTER
  # TextHygiene - deterministic pre-write normalization for edited files
  module TextHygiene
    module_function

    def normalize(content, filename: nil, ensure_final_newline: true)
      return content unless content.is_a?(String)

      out = content.dup

      # Normalize line endings first.
      out.gsub!("\r\n", "\n")
      out.gsub!("\r", "\n")

      # Remove BOM and zero-width chars that often create invisible diffs.
      out.sub!(/\A\xEF\xBB\xBF/, "")
      out.gsub!(/[\u200B\u200C\u200D\uFEFF]/, "")

      # Remove control chars except tab/newline.
      out.gsub!(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/, "")

      # Strip trailing spaces per line.
      out.gsub!(/[ \t]+$/, "")

      # Ensure newline at EOF for text files.
      if ensure_final_newline && text_like?(filename) && !out.empty? && !out.end_with?("\n")
        out << "\n"
      end

      out
    end

    def text_like?(filename)
      return true if filename.nil?

      ext = File.extname(filename.to_s).downcase
      !%w[.png .jpg .jpeg .gif .webp .pdf .zip .gz .tgz .mp3 .mp4 .mov .avi .woff .woff2].include?(ext)
    end
  end
end
