# frozen_string_literal: true

module Master
  module Judge
    module Scan
      Finding = Data.define(:rule, :rule_id, :message, :line, :severity, :fix, :tags, :reversibility, :blast_radius) do
        def self.build(rule:, message:, line:, severity: :warning, fix: nil, tags: [], reversibility: nil, blast_radius: nil)
          new(rule:, rule_id: rule.to_s, message:, line:, severity:, fix:, tags:, reversibility:, blast_radius:)
        end

        def [](key)
          public_send(key)
        end

        def to_h
          { rule:, rule_id:, message:, line:, severity:, fix:, tags:, reversibility:, blast_radius: }
        end

        def merge(extras) = to_h.merge(extras)
      end
    end
  end
end
