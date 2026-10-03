# frozen_string_literal: true

require_relative "test_helper"

class TestLawVocabulary < Minitest::Test
  def test_normative_terms_normalize_to_law
    %w[
      law laws rule rules principle principles convention conventions
      standard standards guideline guidelines heuristic heuristics
      precept tenet canon norm doctrine
    ].each do |term|
      assert_equal "law", Master::LawVocabulary.normalize(term)
    end
  end

  def test_multiword_guidance_terms_normalize_to_law
    %w[usability heuristic design principle style guide].each do |term|
      assert_equal "law", Master::LawVocabulary.normalize(term)
    end
  end

  def test_related_terms_keep_their_technical_identity
    %w[policy constraint invariant criterion practice].each do |term|
      refute_equal "law", Master::LawVocabulary.normalize(term)
      assert_equal :related, Master::LawVocabulary.relation(term)
    end
  end

  def test_synonymy_is_symmetric
    assert Master::LawVocabulary.synonymous?("heuristic", "rule")
    assert Master::LawVocabulary.synonymous?("RULE", "principle")
    refute Master::LawVocabulary.synonymous?("policy", "rule")
  end

  def test_unknown_terms_are_preserved
    assert_equal "advice", Master::LawVocabulary.normalize("advice")
    refute Master::LawVocabulary.known?("advice")
  end

  def test_prompt_explains_the_canonical_term
    prompt = Master::LawVocabulary.prompt

    assert_includes prompt, "law is MASTER's canonical term"
    assert_includes prompt, "heuristic"
    assert_includes prompt, "policy"
  end
end
