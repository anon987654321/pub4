# frozen_string_literal: true

require "yaml"
require_relative "test_helper"

class TestSynonymsContract < Minitest::Test
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
    assert_equal "MASTER/gates/gates.yml", data.fetch("authority").fetch("check_execution_registry")
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
end
