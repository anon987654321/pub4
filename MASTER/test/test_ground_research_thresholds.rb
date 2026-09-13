# frozen_string_literal: true

require_relative "test_helper"

# ResearchThresholds is a cited table the brain overlay reads, and the brief
# restates its thresholds in prose, so the prose is held to the table it
# describes.
class TestGroundResearchThresholds < Minitest::Test
  RT = Master::Ground::ResearchThresholds

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
