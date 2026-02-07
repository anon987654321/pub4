# frozen_string_literal: true

module MASTER
  module FileHygiene
    class << self
      # Phase 1: Deterministic cleanup, no LLM needed
      def clean(text)
        text = strip_crlf(text)
        text = strip_trailing_whitespace(text)
        text = strip_bom(text)
        text = strip_zero_width(text)
        text = ensure_final_newline(text)
        text
      end

      def strip_crlf(text)
        text.gsub("\r\n", "\n").gsub("\r", "\n")
      end

      def strip_trailing_whitespace(text)
        text.each_line.map { |line| line.rstrip }.join("\n")
      end

      def strip_bom(text)
        text.sub(/\A\xEF\xBB\xBF/, "")
      end

      def strip_zero_width(text)
        # Remove zero-width spaces, joiners, non-joiners (outside code blocks)
        text.gsub(/[\u200B\u200C\u200D\uFEFF]/, "")
      end

      def ensure_final_newline(text)
        text.end_with?("\n") ? text : "#{text}\n"
      end
    end
  end
end
