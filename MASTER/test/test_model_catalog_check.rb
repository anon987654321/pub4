# frozen_string_literal: true

require_relative "test_helper"
require_relative "../tools/model_catalog_check"

# "No longer served" is three problems with three different fixes, and the
# difference is what makes the report actionable rather than a list. The check
# itself needs the network; this pins the judgement that does not.
class ModelCatalogCheckTest < Minitest::Test
  LIVE = [
    "z-ai/glm-4.5-air", "z-ai/glm-4.6",
    "meta-llama/llama-4-scout", "meta-llama/llama-3.3-70b-instruct",
    "cohere/command-a", "cohere/command-r-plus-08-2024",
    "google/gemma-3-4b-it",
  ].freeze

  def classify(id) = Pub4::ModelCatalogCheck.nearest(id, LIVE)

  def test_a_withdrawn_free_tier_points_at_the_paid_variant
    assert_equal [:free_tier_withdrawn, "z-ai/glm-4.5-air"], classify("z-ai/glm-4.5-air:free")
  end

  def test_a_renamed_model_points_at_the_new_name
    assert_equal [:renamed, "cohere/command-r-plus-08-2024"], classify("cohere/command-r-plus")
  end

  def test_a_vendor_the_provider_dropped_has_no_suggestion
    assert_equal [:vendor_absent, nil], classify("cerebras/llama-3.1-8b")
  end

  # The fallback that used to sit here offered the vendor's shortest id, which
  # answered "gemini-flash-lite is gone" with "use gemma-3-4b-it" — a wrong
  # answer in the shape of a right one. Saying nothing is the better answer.
  def test_no_plausible_successor_suggests_nothing
    assert_equal [:no_successor, nil], classify("google/gemini-flash-lite-latest")
  end

  def test_only_vendor_scoped_ids_are_checkable
    assert Pub4::ModelCatalogCheck.checkable?("z-ai/glm-4.6")
    refute Pub4::ModelCatalogCheck.checkable?("gemini-2.5-pro"), "a bare id addresses a native API"
    refute Pub4::ModelCatalogCheck.checkable?("ollama:phi4:mini")
    refute Pub4::ModelCatalogCheck.checkable?("web-chat:grok")
  end

  # The registry it reads is the live one, so this fails when models.yml grows a
  # chain shape the reader does not recognise.
  def test_it_finds_the_real_chains
    chains = Pub4::ModelCatalogCheck.chains

    refute_empty chains
    assert chains.key?("models.fast"), "models.fast is a fallback chain and must be read as one"
  end
end
