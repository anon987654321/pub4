# frozen_string_literal: true

require "yaml"
require_relative "test_helper"

class TestSynonymsContract < Minitest::Test
  EXECUTION_FIELDS = %w[class covered_by env_flags gap needs pass require script].freeze
  POLICY_FIELDS = %w[law laws law_id law_ids rule rules policy severity tier statement rationale provenance].freeze

  def vocabulary
    YAML.safe_load_file(File.join(Master::ROOT, "docs", "synonyms.yml"))
  end

  def test_glossary_is_data_only_and_names_the_existing_authority
    data = vocabulary

    assert_equal 1, data.fetch("schema")
    assert_equal "glossary_only", data.fetch("purpose")
    assert_equal "none", data.fetch("runtime_effect")
    assert_equal "MASTER/data/soul.yml", data.fetch("authority").fetch("constitution")
    assert_equal "MASTER/data/laws.yml", data.fetch("authority").fetch("law_catalogue")
    assert_equal "MASTER/checks/checks.yml", data.fetch("authority").fetch("check_execution_registry")
  end

  def test_check_proof_and_result_states_are_not_collapsed_into_synonyms
    terms = vocabulary.fetch("terms")

    assert_equal "Law", terms.fetch("law").fetch("preferred")
    assert_equal "check", terms.fetch("check").fetch("preferred")
    assert_equal ["gate"], terms.fetch("check").fetch("legacy_aliases")
    assert_equal %w[Law check], terms.fetch("proof").fetch("not_synonyms_of")
    assert_equal %w[inconclusive gap], terms.fetch("skip").fetch("not_synonyms_of")
    assert_equal %w[hard ops soft], vocabulary.fetch("not_enforced_tiers").sort
  end
  def check_registry
    YAML.safe_load_file(File.join(Master::ROOT, "checks", "checks.yml"))
  end

  def test_check_registry_remains_execution_inventory_not_a_second_policy_catalogue
    checks = check_registry

    refute_empty checks
    checks.each do |name, declaration|
      assert_kind_of Hash, declaration, "#{name} must declare an instrument"
      keys = declaration.keys.map(&:to_s)
      policy_keys = keys & POLICY_FIELDS
      unknown_keys = keys - EXECUTION_FIELDS
      assert_empty policy_keys, "#{name} duplicates normative metadata in checks.yml"
      assert_empty unknown_keys, "#{name} adds an unreviewed check-registry field"
    end
  end

end
