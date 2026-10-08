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

  def resolver = Master::Ground::LawResolver.new(laws_data: { "laws" => LAWS })

  def test_the_rule_serving_the_higher_priority_law_wins_either_way_round
    assert_equal "SAFE", resolver.winner("TERSE", "SAFE", laws_index: INDEX)
    assert_equal "SAFE", resolver.winner("SAFE", "TERSE", laws_index: INDEX)
  end

  def test_a_tie_keeps_the_first_rule
    assert_equal "TERSE", resolver.winner("TERSE", "UNTIERED", laws_index: INDEX)
    assert_equal "UNTIERED", resolver.winner("UNTIERED", "TERSE", laws_index: INDEX)
  end

  def test_tier_places_a_rule_with_no_declared_law
    assert_equal "ABSTRACTION", resolver.law_for("layered", laws_index: INDEX)
    assert_equal "DENSITY", resolver.law_for("UNTIERED", laws_index: INDEX)
  end

  def test_an_unknown_rule_or_law_ranks_last
    assert_nil resolver.law_for("NOPE", laws_index: INDEX)
    assert_equal 99, resolver.priority(nil)
    assert_equal "LAYERED", resolver.winner("NOPE", "LAYERED", laws_index: INDEX)
  end

  def test_reads_the_real_laws_from_laws_yml
    real = Master::Ground::LawResolver.new

    assert_equal 1, real.priority("ROBUSTNESS")
    assert_equal 2, real.priority("ABSTRACTION")
    assert_equal 6, real.priority("DENSITY")
  end

  def test_applicable_laws_always_include_the_governing_roots
    selection = Master::Ground::ApplicableLaws.new.for(path: File.join(Master::ROOT, "lib", "master.rb"))

    %w[CAPABILITY_STATUS_MUST_BE_TRUTHFUL ROBUSTNESS SINGULARITY LINEARITY PROXIMITY
       ABSTRACTION DENSITY RENDERED_VALUES].each do |law|
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
