# frozen_string_literal: true

require_relative "test_helper"

# LawResolver settles two rules that want the same lines by the priority of the
# law each one serves: lower number wins, a tie keeps the first, and a rule
# with no declared law is placed by its tier.
class TestGroundLawResolver < Minitest::Test
  LAWS = { "ROBUSTNESS" => { "priority" => 1 }, "DENSITY" => { "priority" => 3 },
           "ABSTRACTION" => { "priority" => 2 } }.freeze
  INDEX = {
    "SAFE" => { "violates_law" => "ROBUSTNESS" },
    "TERSE" => { "supports_law" => "DENSITY" },
    "LAYERED" => { "tier" => "architecture" },
    "UNTIERED" => { "tier" => "whatever" },
  }.freeze

  def resolver = Master::Ground::LawResolver.new(rules_data: { "laws" => LAWS })

  def test_the_rule_serving_the_higher_priority_law_wins_either_way_round
    assert_equal "SAFE", resolver.winner("TERSE", "SAFE", rules_index: INDEX)
    assert_equal "SAFE", resolver.winner("SAFE", "TERSE", rules_index: INDEX)
  end

  def test_a_tie_keeps_the_first_rule
    assert_equal "TERSE", resolver.winner("TERSE", "UNTIERED", rules_index: INDEX)
    assert_equal "UNTIERED", resolver.winner("UNTIERED", "TERSE", rules_index: INDEX)
  end

  def test_tier_places_a_rule_with_no_declared_law
    assert_equal "ABSTRACTION", resolver.law_for("layered", rules_index: INDEX)
    assert_equal "DENSITY", resolver.law_for("UNTIERED", rules_index: INDEX)
  end

  def test_an_unknown_rule_or_law_ranks_last
    assert_nil resolver.law_for("NOPE", rules_index: INDEX)
    assert_equal 99, resolver.priority(nil)
    assert_equal "LAYERED", resolver.winner("NOPE", "LAYERED", rules_index: INDEX)
  end

  def test_reads_the_real_laws_from_rules_yml
    real = Master::Ground::LawResolver.new

    assert_operator real.priority("ROBUSTNESS"), :<, 99, "the constitution declares ROBUSTNESS a law"
  end
end
