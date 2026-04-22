# frozen_string_literal: true

require_relative "test_helper"

class TestBridgesRepligen < Minitest::Test
  def test_model_catalog_has_required_categories
    catalog = MASTER::Bridges::ReplicateBridge.model_catalog
    assert catalog.key?(:image_gen)
    assert catalog.key?(:video_gen)
    assert catalog.key?(:enhance)
    assert catalog.key?(:audio)
  end

  def test_model_catalog_image_gen_is_non_empty_array
    models = MASTER::Bridges::ReplicateBridge.model_catalog[:image_gen]
    assert_kind_of Array, models
    refute_empty models
  end

  def test_model_catalog_entries_have_model_and_name_keys
    MASTER::Bridges::ReplicateBridge.model_catalog.each_value do |entries|
      entries.each do |entry|
        assert entry.key?(:model), "Entry #{entry.inspect} missing :model"
        assert entry.key?(:name),  "Entry #{entry.inspect} missing :name"
      end
    end
  end

  def test_models_for_returns_array_for_valid_category
    result = MASTER::Bridges::ReplicateBridge.models_for(:image_gen)
    assert_kind_of Array, result
    refute_empty result
  end

  def test_models_for_returns_empty_for_unknown_category
    result = MASTER::Bridges::ReplicateBridge.models_for(:nonexistent)
    assert_kind_of Array, result
    assert_empty result
  end

  def test_categories_returns_all_catalog_keys
    cats = MASTER::Bridges::ReplicateBridge.categories
    assert_includes cats, :image_gen
    assert_includes cats, :video_gen
    assert_includes cats, :enhance
  end

  def test_generate_image_returns_error_without_api_key
    ENV["REPLICATE_API_TOKEN"] = nil
    ENV["REPLICATE_API_KEY"]   = nil
    result = MASTER::Bridges::ReplicateBridge.generate_image(prompt: "test prompt")
    assert result.err?
  end

  def test_catwalk_styles_constant_defined
    assert_kind_of Array, MASTER::Bridges::ReplicateBridge::CATWALK_STYLES
    refute_empty MASTER::Bridges::ReplicateBridge::CATWALK_STYLES
  end

  def test_catwalk_lighting_constant_defined
    assert_kind_of Array, MASTER::Bridges::ReplicateBridge::CATWALK_LIGHTING
    refute_empty MASTER::Bridges::ReplicateBridge::CATWALK_LIGHTING
  end
end
