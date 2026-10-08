# frozen_string_literal: true

module Master
  module Review
    module Scan
      # No hypothesis-or-measured status. Every finding is measured against the
      # source its detector read, and one that guesses says so in confidence and
      # why, which Scanner#should_autofix? reads. test_finding_metadata.rb holds
      # the shape.
      Finding = Data.define(
        :law, :law_id, :message, :line, :severity, :fix, :tags,
        :reversibility, :blast_radius, :confidence, :why, :genealogy,
        :dedupe_key, :impact_radius
      ) do
        def self.build(
          law:, message:, line:, severity: :warning, fix: nil, tags: [],
          reversibility: nil, blast_radius: nil, confidence: nil, why: nil,
          genealogy: nil, dedupe_key: nil, impact_radius: nil
        )
          new(law:, law_id: law.to_s, message:, line:, severity:, fix:, tags:,
            reversibility:, blast_radius:, confidence:, why:, genealogy:,
            dedupe_key:, impact_radius:)
        end

        def [](key)
          public_send(key)
        end

        # A finding reaches a reader as this object from a rule and as the plain
        # symbol-keyed Hash scan_dir returns — the trap AGENTS.md records, where
        # `f.law` raises on one and `h[:law]` works on both. #[] above is what
        # makes one subscript read either, and four readers hand-rolled the same
        # respond_to? ladder around it anyway. Two of them disagreed about to_s.
        # The reader comes first and the subscript second, which is not
        # redundant: a test double is often a bare Data.define with no #[], and
        # narrowing this to the subscript alone silently returned nil for one.
        # Anything answering neither gets nil rather than an exception, because
        # a law may return whatever it likes and a reporter must not be the
        # thing that fails.
        def self.read(finding, key)
          return finding.public_send(key) if finding.respond_to?(key)

          finding[key] if finding.respond_to?(:[])
        end

        def to_h
          {
            law:,
            law_id:
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

        def to_proof(source: :deterministic, status: :open, subject: nil, evidence: nil)
          Master::Proof.build(
            claim: message,
            law: law_id || law,
            subject:,
            evidence: evidence || message,
            source:,
            status:,
            metadata: to_h,
          )
        end

        def merge(extras)
          to_h.merge(extras)
        end
      end
    end
  end
end
