# frozen_string_literal: true

module Master
  module Judge
    module Scan
      # O708: formal value object for violation hashes flowing through RuleLoop/FixPipeline.
      Violation = Data.define(:file, :line, :rule, :message, :severity, :fix, :confidence, :ext) do
        SEVERITY_RANK = Master::SEVERITY_RANK

        def self.from_hash(hash)
          return nil unless hash.is_a?(Hash)

          new(
            file: hash[:file] || hash["file"],
            line: hash[:line] || hash["line"],
            rule: hash[:rule] || hash["rule"],
            message: hash[:message] || hash["message"],
            severity: (hash[:severity] || hash["severity"] || :info).to_sym,
            fix: hash[:fix] || hash["fix"],
            confidence: hash[:confidence] || hash["confidence"],
            ext: hash[:ext] || hash["ext"]
          )
        end

        def severity_rank
          SEVERITY_RANK.fetch(severity, 0)
        end

        def to_h
          { file:, line:, rule:, message:, severity:, fix:, confidence:, ext: }.compact
        end

        def self.meets_threshold?(violation, min_severity: :warning)
          rank = SEVERITY_RANK.fetch(min_severity.to_sym, 0)
          from_hash(violation)&.severity_rank.to_i >= rank
        end
      end
    end
  end
end