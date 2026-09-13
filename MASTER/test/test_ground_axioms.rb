# frozen_string_literal: true

require_relative "test_helper"

# Axioms and ResearchThresholds are cited tables: design.rb, the Rails audits
# and the brain overlay read their numbers and their citation strings. The
# citations are what an operator sees, and the brief restates the thresholds
# in prose, so the prose is held to the table it describes.
class TestGroundAxioms < Minitest::Test
  AX = Master::Ground::Axioms
  RT = Master::Ground::ResearchThresholds

  def test_citations_name_their_source
    assert_equal "[Rails Doctrine — Value integrated systems] one box", AX::RailsDoctrine.cite(:integrated, "one box")
    assert_equal "[Rails Doctrine — made_up] why", AX::RailsDoctrine.cite(:made_up, "why")
    assert_equal "[Nielsen #9 — Help Users Recognize, Diagnose, and Recover from Errors] vague",
                 AX::UxHeuristics.cite(:h9_error_recovery, "vague")
    assert_equal "[WCAG 2.5.8 AA — Target Size (Minimum)] 20px", AX::Wcag.cite("2.5.8", "20px")
    assert_equal "[WCAG 9.9.9] unknown", AX::Wcag.cite("9.9.9", "unknown")
  end

  def test_heuristic_numbers_parse_two_digits
    assert_equal 10, AX::UxHeuristics.number(:h10_help)
    assert_equal 1, AX::UxHeuristics.number(:h1_visibility)
  end

  def test_every_signal_names_a_declared_heuristic
    AX::UxHeuristics::SIGNALS.each_value do |signals|
      signals.each_key { |key| assert AX::UxHeuristics::HEURISTICS.key?(key), "#{key} is not a heuristic" }
    end
  end

  def test_wcag_constants_agree_with_the_criteria_they_come_from
    assert_equal "AA", AX::Wcag.find("1.4.3").level.to_s
    assert_match(/#{AX::Wcag::CONTRAST_NORMAL}:1/, AX::Wcag.find("1.4.3").requirement)
    assert_match(/#{AX::Wcag::TOUCH_TARGET_AA_PX}x#{AX::Wcag::TOUCH_TARGET_AA_PX}/, AX::Wcag.find("2.5.8").requirement)
    assert_nil AX::Wcag.find("0.0.0")
  end

  def test_the_research_brief_restates_the_thresholds_it_names
    brief = RT.brief

    assert_includes brief, "#{(RT.threshold(:clone_similarity) * 100).round}% similarity"
    assert_includes brief, "#{RT.threshold(:duplicate_min_tokens)}+ tokens"
    assert_includes brief, "#{RT.threshold(:api_timeout_s)}s request timeout"
    assert_includes brief, "#{RT.threshold(:connect_timeout_s)}s connect timeout"
    assert_includes brief, "capped at #{RT.threshold(:max_backoff_s)}s"
    assert_includes brief, "#{(RT.threshold(:circuit_error_rate) * 100).round}% circuit-breaker"
    assert_includes brief, "#{RT.threshold(:attention_sink_tokens)} attention-sink tokens"
    assert_includes brief, "#{RT.threshold(:rag_chunk_tokens)}-token"
    assert_includes brief, "#{RT.threshold(:semantic_entropy_samples)} semantic-entropy samples"
  end

  def test_an_unknown_threshold_raises_rather_than_reading_nil
    assert_raises(KeyError) { RT.threshold(:not_a_threshold) }
  end
end
