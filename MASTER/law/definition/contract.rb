# frozen_string_literal: true

module Law
  # Generated projection of the executable constitution. The laws remain
  # ONE_SOURCE; this contract gives external models the same procedure and a
  # portable law identity without maintaining a second rule catalogue.
  module Contract
    module_function

    VERSION = 2
    PROTOCOL = [
      "IDENTIFY: state the task and intended effects before acting.",
      "READ: load the applicable constitution/laws before deciding.",
      "EVIDENCE: distinguish observed facts, inference, and proposal.",
      "CHECK: apply every applicable law; do not stop at the first convenient rule.",
      "PREFER: resolve conflicts by declared priority and safety constraints.",
      "SIMULATE: inspect edge cases, security, scope, reversibility, and side effects.",
      "ADMIT: only execute effects that pass the constitutional check.",
      "VERIFY: inspect the actual result; never claim completion without evidence.",
      "REPAIR: if a law is violated, correct the artifact and re-check from the start.",
      "REPORT: state what happened, what was verified, and what remains unresolved.",
    ].freeze

    POLICY = {
      "lifecycle" => {
        "states" => Definition::LIFECYCLE_TRANSITIONS.keys.map(&:to_s),
        "transitions" => Definition::LIFECYCLE_TRANSITIONS
          .transform_keys(&:to_s)
          .transform_values { |states| states.map(&:to_s) },
      },
      "autofix" => {
        "policies" => AUTOFIX_POLICIES.map(&:to_s),
        "automatic_requires_deterministic_detector" => true,
      },
      "universality" => {
        "law_is_universal" => true,
        "detectors_may_be_domain_specific" => true,
      },
      "vocabulary" => Master::LawVocabulary::TERMS,
      "proof" => {
        "deterministic" => "bad and good fixtures prove detector polarity.",
        "semantic" => "bad and good examples accompany the question; model evaluation is required.",
        "practice" => "the law is conduct guidance and has no source detector.",
      },
    }.freeze

    def render(full: false)
      entries = Law.definitions.values.sort_by { |law| law.id.to_s }.map(&:contract_entry)
      transformation_policy = Master.law("transformation_policy")
      laws = full ? entries : entries.map { |entry| entry.slice("id", "severity", "mode", "languages", "question") }
      source = canonical_source
      JSON.pretty_generate(
        "contract_version" => VERSION,
        "law_digest" => contract_digest(entries, transformation_policy, source),
        "protocol" => PROTOCOL,
        "law_policy" => POLICY,
        "transformation_policy" => transformation_policy,
        "law_source" => source.slice("governing_laws", "law_map_digest"),
        "laws" => laws,
      )
    end

    def digest
      entries = Law.definitions.values.sort_by { |law| law.id.to_s }.map(&:contract_entry)
      contract_digest(entries, Master.law("transformation_policy"), canonical_source)
    end

    def canonical_source
      roots = Master.law_entries.sort_by { |entry| [entry["priority"].to_i, entry["id"].to_s] }.map do |entry|
        {
          "id" => entry["id"].to_s,
          "priority" => entry["priority"].to_i,
          "statement" => entry["statement"].to_s,
          "applies_to" => Array(entry["applies_to"]).map(&:to_s),
        }
      end
      law_map = Master.law("law_map")
      {
        "governing_laws" => roots,
        "law_map_digest" => Digest::SHA256.hexdigest(JSON.generate(law_map)),
      }
    end

    def contract_digest(entries, transformation_policy, source)
      Digest::SHA256.hexdigest(
        JSON.generate(
          "contract_version" => VERSION,
          "protocol" => PROTOCOL,
          "law_policy" => POLICY,
          "transformation_policy" => transformation_policy,
          "law_source" => source,
          "laws" => entries,
        ),
      )
    end
  end
end
