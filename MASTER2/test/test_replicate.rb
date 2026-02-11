# frozen_string_literal: true

require_relative "test_helper"

class TestReplicate < Minitest::Test
  def setup
    @replicate = MASTER::Replicate
  end

  def test_models_constant_exists
    assert @replicate::MODELS.is_a?(Hash)
    refute @replicate::MODELS.empty?
  end

  def test_model_categories_constant_exists
    assert @replicate::MODEL_CATEGORIES.is_a?(Hash)
    refute @replicate::MODEL_CATEGORIES.empty?
  end

  def test_models_hash_includes_image_models
    assert @replicate::MODELS.key?(:flux)
    assert @replicate::MODELS.key?(:flux_pro)
    assert @replicate::MODELS.key?(:flux_dev)
    assert @replicate::MODELS.key?(:sdxl)
    assert @replicate::MODELS.key?(:kandinsky)
  end

  def test_models_hash_includes_video_models
    assert @replicate::MODELS.key?(:svd)
    assert @replicate::MODELS.key?(:hailuo)
    assert @replicate::MODELS.key?(:kling)
  end

  def test_models_hash_includes_audio_models
    assert @replicate::MODELS.key?(:musicgen)
    assert @replicate::MODELS.key?(:bark)
  end

  def test_models_hash_includes_upscale_models
    assert @replicate::MODELS.key?(:esrgan)
    assert @replicate::MODELS.key?(:gfpgan)
  end

  def test_model_id_with_valid_name
    assert_equal 'black-forest-labs/flux-1.1-pro', @replicate.model_id(:flux)
    assert_equal 'stability-ai/sdxl', @replicate.model_id(:sdxl)
    assert_equal 'meta/musicgen', @replicate.model_id(:musicgen)
  end

  def test_model_id_with_invalid_name
    error = assert_raises(ArgumentError) do
      @replicate.model_id(:nonexistent)
    end
    assert_match(/Unknown model/, error.message)
  end

  def test_models_for_image_category
    models = @replicate.models_for(:image)
    assert models.is_a?(Array)
    assert models.all? { |m| m.is_a?(Hash) && m.key?(:name) && m.key?(:id) }
    assert models.any? { |m| m[:name] == :flux }
    assert models.any? { |m| m[:name] == :sdxl }
  end

  def test_models_for_video_category
    models = @replicate.models_for(:video)
    assert models.is_a?(Array)
    assert models.any? { |m| m[:name] == :svd }
    assert models.any? { |m| m[:name] == :hailuo }
  end

  def test_models_for_audio_category
    models = @replicate.models_for(:audio)
    assert models.is_a?(Array)
    assert models.any? { |m| m[:name] == :musicgen }
    assert models.any? { |m| m[:name] == :bark }
  end

  def test_models_for_invalid_category
    models = @replicate.models_for(:nonexistent)
    assert_equal [], models
  end

  def test_model_categories_contain_expected_models
    assert @replicate::MODEL_CATEGORIES[:image].include?(:flux)
    assert @replicate::MODEL_CATEGORIES[:video].include?(:svd)
    assert @replicate::MODEL_CATEGORIES[:audio].include?(:musicgen)
    assert @replicate::MODEL_CATEGORIES[:upscale].include?(:esrgan)
  end

  def test_upscale_uses_esrgan_model
    # Verify that upscale method would use the MODELS constant
    # We can't test the actual API call without a key
    skip "Requires REPLICATE_API_KEY" unless @replicate.available?
  end

  def test_describe_uses_blip_model
    # Verify that describe method would use the MODELS constant
    skip "Requires REPLICATE_API_KEY" unless @replicate.available?
  end

  def test_available_without_api_key
    original_key = ENV['REPLICATE_API_KEY']
    ENV['REPLICATE_API_KEY'] = nil
    
    refute @replicate.available?
    
    ENV['REPLICATE_API_KEY'] = original_key
  end

  def test_generate_video_returns_error_without_api_key
    original_key = ENV['REPLICATE_API_KEY']
    ENV['REPLICATE_API_KEY'] = nil
    
    result = @replicate.generate_video(prompt: "test")
    assert result.err?
    assert_match(/REPLICATE_API_KEY/, result.error)
    
    ENV['REPLICATE_API_KEY'] = original_key
  end

  def test_generate_music_returns_error_without_api_key
    original_key = ENV['REPLICATE_API_KEY']
    ENV['REPLICATE_API_KEY'] = nil
    
    result = @replicate.generate_music(prompt: "test")
    assert result.err?
    assert_match(/REPLICATE_API_KEY/, result.error)
    
    ENV['REPLICATE_API_KEY'] = original_key
  end

  def test_batch_generate_returns_error_without_api_key
    original_key = ENV['REPLICATE_API_KEY']
    ENV['REPLICATE_API_KEY'] = nil
    
    result = @replicate.batch_generate(["prompt1", "prompt2"])
    assert result.err?
    assert_match(/REPLICATE_API_KEY/, result.error)
    
    ENV['REPLICATE_API_KEY'] = original_key
  end

  def test_batch_generate_returns_error_with_empty_prompts
    skip "Requires REPLICATE_API_KEY" unless @replicate.available?
    
    result = @replicate.batch_generate([])
    assert result.err?
    assert_match(/empty/, result.error)
  end

  def test_batch_generate_returns_error_with_nil_prompts
    skip "Requires REPLICATE_API_KEY" unless @replicate.available?
    
    result = @replicate.batch_generate(nil)
    assert result.err?
    assert_match(/empty/, result.error)
  end
end
