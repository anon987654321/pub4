require "digest"

# frozen_string_literal: true

module Master
  module Fix
    Violation = Struct.new(:file, :line, :law, :message, :severity, :fix, :confidence, :ext, :fingerprint,
                           :reversibility, :blast_radius, keyword_init: true) do
      def self.from_finding(finding, file:, ext: nil)
        data = finding.respond_to?(:to_h) ? finding.to_h : finding
        new(
          file:,
          line: data[:line] || data["line"],
          law: data[:law] || data[:law_id] || data["law"] || data["law_id"],
          message: data[:message] || data["message"],
          severity: data[:severity] || data["severity"],
          fix: data[:fix] || data["fix"],
          confidence: data[:confidence] || data["confidence"],
          ext:,
          fingerprint: data[:fingerprint] || data["fingerprint"],
          reversibility: data[:reversibility] || data["reversibility"],
          blast_radius: data[:blast_radius] || data["blast_radius"],
        )
      end

      def evidence_key
        Digest::SHA256.hexdigest(
          [law, file, line, fingerprint, message].map(&:to_s).join("\0")
        )[0, 24]
      end

      def [](key)
        public_send(key.to_sym)
      end

      def to_h
        {
          file:,
          line:,
          law:,
          message:,
          severity:,
          fix:,
          confidence:,
          ext:,
          fingerprint:,
          reversibility:,
          blast_radius:,
        }.compact
      end
    end
  end
end
