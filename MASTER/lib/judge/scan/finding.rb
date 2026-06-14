# frozen_string_literal: true

module Master
  module Judge
    module Scan
      Finding = Data.define(
        :rule, :rule_id, :message, :line, :severity, :fix, :tags,
        :reversibility, :blast_radius, :confidence, :why, :genealogy,
        :dedupe_key, :impact_radius
      ) do
        def self.build(
          rule:, message:, line:, severity: :warning, fix: nil, tags: [],
          reversibility: nil, blast_radius: nil, confidence: nil, why: nil,
          genealogy: nil, dedupe_key: nil, impact_radius: nil
        )
          new(
            rule: rule,
            rule_id: rule.to_s,
            message: message,
            line: line,
            severity: severity,
            fix: fix,
            tags: tags,
            reversibility: reversibility,
            blast_radius: blast_radius,
            confidence: confidence,
            why: why,
            genealogy: genealogy,
            dedupe_key: dedupe_key,
            impact_radius: impact_radius
          )
        end

        def [](key)
          public_send(key)
        end

        def to_h
          {
            rule: rule,
            rule_id: rule_id,
            message: message,
            line: line,
            severity: severity,
            fix: fix,
            tags: tags,
            reversibility: reversibility,
            blast_radius: blast_radius,
            confidence: confidence,
            why: why,
            genealogy: genealogy,
            dedupe_key: dedupe_key,
            impact_radius: impact_radius
          }.compact
        end

        def merge(extras)
          to_h.merge(extras)
        end
      end
    end
  end
end
