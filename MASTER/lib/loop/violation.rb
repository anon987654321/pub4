# frozen_string_literal: true

module Master
  module Loop
    Violation = Struct.new(:file, :line, :rule, :message, :severity, :fix, :confidence, :ext, keyword_init: true) do
      def self.from_finding(finding, file:, ext: nil)
        data = finding.respond_to?(:to_h) ? finding.to_h : finding
        new(
          file: file,
          line: data[:line] || data["line"],
          rule: data[:rule] || data[:rule_id] || data["rule"] || data["rule_id"],
          message: data[:message] || data["message"],
          severity: data[:severity] || data["severity"],
          fix: data[:fix] || data["fix"],
          confidence: data[:confidence] || data["confidence"],
          ext: ext
        )
      end

      def [](key)
        public_send(key.to_sym)
      end

      def to_h
        {
          file: file,
          line: line,
          rule: rule,
          message: message,
          severity: severity,
          fix: fix,
          confidence: confidence,
          ext: ext
        }.compact
      end
    end
  end
end
