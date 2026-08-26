# frozen_string_literal: true

module Master
  module Ground
    class Redactor
      KEY_PATTERNS = [
        /sk-[A-Za-z0-9_\-]{16,}/,
        /sk-ant-[A-Za-z0-9_\-]{16,}/,
        /Bearer\s+[A-Za-z0-9_\-\.]{16,}/i,
        /\b[A-Za-z0-9]{32,}\b/,
      ].freeze

      SENSITIVE_KEYS = /
        \A(?:password|passwd|secret|token|api[_-]?key|authorization|cookie|private[_-]?key)\z
      /ix

      DMESG_MAX = 240

      def self.text(value)
        out = value.to_s
        KEY_PATTERNS.each { |pattern| out = out.gsub(pattern, "[REDACTED]") }
        out
      end

      def self.payload(hash)
        hash.each_with_object({}) do |(key, value), out|
          out[key] = scrub_value(key, value)
        end
      end

      def self.scrub_value(key, value)
        return "[REDACTED]" if key.to_s.match?(SENSITIVE_KEYS)

        case value
        when Hash then payload(value)
        when Array then value.map { |item| scrub_value(key, item) }
        when String then truncate(text(value))
        else value
        end
      end

      def self.truncate(value)
        text = value.to_s
        return text if text.length <= DMESG_MAX

        "#{text[0, DMESG_MAX]}…"
      end

      def self.public_error_message
        "An internal error occurred. Retry or check server logs."
      end
    end
  end
end
