# frozen_string_literal: true

module Law
  # Derived law index. Identity, enforcement surface, lifecycle, proof and
  # universality stay on Law::Definition; this index is generated and never authoritative.
  module Index
    module_function

    VERSION = 1

    def rows(definitions = Law.definitions.values)
      definitions.sort_by { |law| law.id.to_s }.map do |law|
        {
          "id" => law.id.to_s,
          "scope" => law.scope.to_s,
          "surfaces" => law.assessment_surfaces.map(&:to_s),
          "law_scope" => law.law_scope.to_s,
          "languages" => law.languages.map(&:to_s),
          "lifecycle" => law.lifecycle.to_s,
          "autofix" => law.autofix.to_s,
          "proof" => law.proof_kind.to_s,
          "deterministic" => law.scannable?,
          "semantic" => law.semantic?,
          "practice" => !law.practice.nil?,
        }
      end
    end

    def validate!(definitions = Law.definitions.values)
      raise ArgumentError, "law index is empty" if definitions.empty?

      ids = definitions.map { |law| law.id.to_s }
      duplicate = ids.tally.select { |_id, count| count > 1 }.keys
      raise ArgumentError, "duplicate executable law ids: #{duplicate.join(', ')}" unless duplicate.empty?

      invalid = definitions.reject { |law| Definition::LIFECYCLE_TRANSITIONS.key?(law.lifecycle) }
      raise ArgumentError, "invalid law lifecycle: #{invalid.map(&:id).join(', ')}" unless invalid.empty?

      invalid = definitions.reject { |law| AUTOFIX_POLICIES.include?(law.autofix) }
      raise ArgumentError, "invalid law autofix policy: #{invalid.map(&:id).join(', ')}" unless invalid.empty?

      automatic = definitions.select { |law| law.autofix == :automatic && !law.scannable? }
      unless automatic.empty?
        raise ArgumentError, "automatic autofix without deterministic detector: #{automatic.map(&:id).join(', ')}"
      end

      rows(definitions)
    end

    def render(definitions = Law.definitions.values)
      entries = validate!(definitions)
      JSON.pretty_generate(
        "index_version" => VERSION,
        "law_count" => entries.length,
        "universal_count" => entries.count { |entry| entry["law_scope"] == "universal" },
        "laws" => entries,
      )
    end
  end
end
