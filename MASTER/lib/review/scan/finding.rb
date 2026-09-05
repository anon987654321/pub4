# frozen_string_literal: true

module Master
  module Review
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
          new(rule:, rule_id: rule.to_s, message:, line:, severity:, fix:, tags:,
            reversibility:, blast_radius:, confidence:, why:, genealogy:,
            dedupe_key:, impact_radius:)
        end

        def [](key)
          public_send(key)
        end

        # A finding reaches a reader as this object from a rule and as the plain
        # symbol-keyed Hash scan_dir returns — the trap AGENTS.md records, where
        # `f.rule` raises on one and `h[:rule]` works on both. #[] above is what
        # makes one subscript read either, and four readers hand-rolled the same
        # respond_to? ladder around it anyway. Two of them disagreed about to_s.
        # The reader comes first and the subscript second, which is not
        # redundant: a test double is often a bare Data.define with no #[], and
        # narrowing this to the subscript alone silently returned nil for one.
        # Anything answering neither gets nil rather than an exception, because
        # a rule may return whatever it likes and a reporter must not be the
        # thing that fails.
        def self.read(finding, key)
          return finding.public_send(key) if finding.respond_to?(key)

          finding[key] if finding.respond_to?(:[])
        end

        def to_h
          {
            rule:,
            rule_id:,
            message:,
            line:,
            severity:,
            fix:,
            tags:,
            reversibility:,
            blast_radius:,
            confidence:,
            why:,
            genealogy:,
            dedupe_key:,
            impact_radius:,
          }.compact
        end

        def merge(extras)
          to_h.merge(extras)
        end
      end
    end
  end
end
