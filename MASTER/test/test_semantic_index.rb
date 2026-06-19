# frozen_string_literal: true

require_relative "test_helper"

# Fuzzy semantic cache: paraphrased prompts (high cosine) hit; dissimilar miss; disabled = no-op.
class TestSemanticIndex < Minitest::Test
  class FakeEmbedder
    def initialize(vectors, enabled: true)
      @vectors = vectors
      @enabled = enabled
    end

    def enabled? = @enabled
    def embed(text) = @vectors[text]

    def cosine(a, b)
      dot = a.zip(b).sum { |x, y| x * y }
      magnitude = Math.sqrt(a.sum { |x| x * x }) * Math.sqrt(b.sum { |y| y * y })
      magnitude.zero? ? 0.0 : dot / magnitude
    end
  end

  def index(vectors, enabled: true, threshold: 0.92)
    embedder = FakeEmbedder.new(vectors, enabled: enabled)
    Master::Reach::SemanticIndex.new(embedder: embedder, threshold: threshold)
  end

  def test_paraphrase_is_a_near_hit
    idx = index("what is X" => [1.0, 0.0, 0.0], "whats X" => [0.99, 0.02, 0.0])
    idx.remember("what is X", "ANSWER")
    assert_equal "ANSWER", idx.nearest("whats X")
  end

  def test_dissimilar_prompt_misses
    idx = index("what is X" => [1.0, 0.0, 0.0], "unrelated" => [0.0, 1.0, 0.0])
    idx.remember("what is X", "ANSWER")
    assert_nil idx.nearest("unrelated")
  end

  def test_fetch_computes_on_miss_then_reuses
    idx = index("q1" => [1.0, 0.0], "q1-ish" => [0.999, 0.01])
    calls = 0
    first = idx.fetch("q1") { calls += 1; "COMPUTED" }
    second = idx.fetch("q1-ish") { calls += 1; "SHOULD_NOT_RUN" }
    assert_equal "COMPUTED", first
    assert_equal "COMPUTED", second
    assert_equal 1, calls
  end

  def test_disabled_embedder_is_a_noop
    idx = index({ "q" => [1.0] }, enabled: false)
    idx.remember("q", "ANSWER")
    assert_nil idx.nearest("q")
  end
end
