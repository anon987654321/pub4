# frozen_string_literal: true

require_relative "test_helper"
# Loads law/, every Law the scanner builds.
require_relative "../lib/review/scan/law_tree"

# A law that takes a model must never run in the lexical pass: every file,
# clean ones included, would pay a model call.
class TestLawTier < Minitest::Test
  # Every detector class a Law names, constructor arguments or not.
  def law_classes
    Master::Review::Scan::LawTree.definitions.filter_map(&:detector).uniq
  end

  def partition(law)
    processor = Master::Fix::Scan::FileProcessor.new
    lexical, structural, semantic = processor.send(:partition_laws, [law], Object.new)
    { lexical:, structural:, semantic: }.find { |_tier, laws| laws.include?(law) }.first
  end

  def test_the_walk_sees_laws
    assert_operator law_classes.size, :>, 20
    assert(law_classes.any? { |klass| klass.method_defined?(:set_agent) }, "no model-backed law found; the walk is blind")
  end

  def test_every_law_that_responds_to_set_agent_is_semantic
    wrong = law_classes.select { |klass| klass.method_defined?(:set_agent) }
                       .reject { |klass| partition(klass.allocate) == :semantic }
    assert_empty wrong.map(&:name), "model-backed laws outside the semantic tier"
  end

  def test_a_law_without_set_agent_never_lands_in_the_semantic_tier_by_accident
    plain = Class.new { def check(*, **) = [] }.new
    assert_equal :lexical, partition(plain)
  end
end
