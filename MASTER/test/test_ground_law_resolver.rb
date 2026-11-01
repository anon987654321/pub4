# frozen_string_literal: true

require_relative "test_helper"
require "master"
require_relative "../lib/ground/law_resolver"

# Conflict resolution follows document order in the canonical law catalogue.
class TestGroundLawResolver < Minitest::Test
  LAWS = {
    "TRUTHFUL_STATUS" => { "node" => "truthful_status", "statement" => "Truth precedes all." },
    "ROBUSTNESS" => { "node" => "robustness", "statement" => "Fail safely." },
    "ABSTRACTION" => { "node" => "abstraction", "statement" => "Keep boundaries sound." },
    "DENSITY" => { "node" => "density", "statement" => "Remove noise." },
  }.freeze

  INDEX = {
    "SAFE" => { "violates_law" => "ROBUSTNESS" },
    "TERSE" => { "supports_law" => "DENSITY" },
    "LAYERED" => { "tier" => "architecture" },
    "UNTIERED" => { "supports_law" => "DENSITY" },
  }.freeze

  def resolver = Master::Ground::LawResolver.new(laws_data: LAWS)

  def test_rule_serving_the_earlier_constitutional_node_wins_in_either_argument_order
    assert_equal "SAFE", resolver.winner("TERSE", "SAFE", laws_index: INDEX)
    assert_equal "SAFE", resolver.winner("SAFE", "TERSE", laws_index: INDEX)
  end

  def test_equal_node_keeps_the_first_rule
    assert_equal "TERSE", resolver.winner("TERSE", "UNTIERED", laws_index: INDEX)
    assert_equal "UNTIERED", resolver.winner("UNTIERED", "TERSE", laws_index: INDEX)
  end

  def test_tier_fallback_resolves_to_an_existing_parent_node
    assert_equal "ABSTRACTION", resolver.law_for("layered", laws_index: INDEX)
    assert_equal "DENSITY", resolver.law_for("UNTIERED", laws_index: INDEX)
  end

  def test_unknown_rule_or_law_comes_after_the_declared_nodes
    assert_nil resolver.law_for("NOPE", laws_index: INDEX)
    assert_equal 99, resolver.precedence_index(nil)
    assert_equal "LAYERED", resolver.winner("NOPE", "LAYERED", laws_index: INDEX)
  end

  def test_reads_order_from_laws_yml_without_numeric_priority_fields
    real = Master::Ground::LawResolver.new

    assert_equal 1, real.precedence_index("ROBUSTNESS")
    assert_equal 5, real.precedence_index("ABSTRACTION")
    assert_equal 6, real.precedence_index("DENSITY")
    refute Master.load_yaml(File.join(Master::ROOT, "data", "laws.yml")).values.any? { |row| row.is_a?(Hash) && row.key?("priority") }
  end

  def test_applicable_laws_always_include_all_nine_governing_nodes
    selection = Master::Ground::ApplicableLaws.new.for(path: File.join(Master::ROOT, "lib", "master.rb"))
    expected = Master::Ground::LawResolver.new.governing_law_ids

    assert_equal 9, expected.size
    expected.each do |law|
      assert_includes selection.governing_ids, law
      assert_includes selection.ids, law
    end
  end

  def test_applicable_laws_use_the_same_language_contract_as_the_scanner
    selection = Master::Ground::ApplicableLaws.new.for(path: File.join(Master::ROOT, "lib", "master.rb"))

    assert_equal "ruby", selection.language
    assert_includes selection.executable_ids, "FROZEN_STRING_LITERAL"
  end
end
