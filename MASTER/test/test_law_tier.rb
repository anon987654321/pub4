# frozen_string_literal: true

require_relative "test_helper"
# Loads the detector tree so Law.registry holds every class the scanner builds.
require_relative "../lib/review/scan/law_dsl"

# A law that takes a model must never run in the lexical pass: every file,
# clean ones included, would pay a model call.
class TestLawTier < Minitest::Test
  SCANNER_EXTRAS = %w[
    CoChangeCouplingLaw LawCoverageLaw RubocopLaw ReekLaw InterconnectLaw
    VetoPatternLaw SemanticLaw AdversarialLaw CommentDriftLaw AstOmissionLaw
    LibRootDisciplineLaw FileSprawlLaw PathPurposeLaw
  ].freeze

  def law_classes
    registry = Master::Review::Scan::Law.registry.select(&:auto_build?)
    extras = SCANNER_EXTRAS.map { |name| Master::Review::Scan::Laws.const_get(name) }
    (registry + extras).uniq
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
