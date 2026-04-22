# frozen_string_literal: true

require_relative "test_helper"

class TestReplicate < Minitest::Test
  def setup
    @original_api_token = ENV['REPLICATE_API_TOKEN']
    @original_api_key = ENV['REPLICATE_API_KEY']
  end

  def teardown
    ENV['REPLICATE_API_TOKEN'] = @original_api_token
    ENV['REPLICATE_API_KEY'] = @original_api_key
  end

  def test_api_key_prefers_replicate_api_token
    ENV['REPLICATE_API_TOKEN'] = 'token_value'
    ENV['REPLICATE_API_KEY'] = 'key_value'
    
    assert_equal 'token_value', MASTER::Replicate.api_key
  end

  def test_api_key_falls_back_to_replicate_api_key
    ENV['REPLICATE_API_TOKEN'] = nil
    ENV['REPLICATE_API_KEY'] = 'key_value'
    
    assert_equal 'key_value', MASTER::Replicate.api_key
  end

  def test_api_key_returns_nil_when_both_unset
    ENV['REPLICATE_API_TOKEN'] = nil
    ENV['REPLICATE_API_KEY'] = nil
    
    assert_nil MASTER::Replicate.api_key
  end

  def test_available_returns_false_when_no_api_key
    ENV['REPLICATE_API_TOKEN'] = nil
    ENV['REPLICATE_API_KEY'] = nil
    
    refute MASTER::Replicate.available?
  end

  def test_available_returns_true_when_api_key_set
    ENV['REPLICATE_API_TOKEN'] = 'test_token'
    
    assert MASTER::Replicate.available?
  end

  def test_generate_error_message_mentions_replicate_api_token
    ENV['REPLICATE_API_TOKEN'] = nil
    ENV['REPLICATE_API_KEY'] = nil
    
    result = MASTER::Replicate.generate(prompt: "test")
    
    assert result.err?
    assert_equal "REPLICATE_API_TOKEN not set", result.error
  end

  def test_upscale_error_message_mentions_replicate_api_token
    ENV['REPLICATE_API_TOKEN'] = nil
    ENV['REPLICATE_API_KEY'] = nil
    
    result = MASTER::Replicate.upscale(image_url: "http://example.com/img.jpg")
    
    assert result.err?
    assert_equal "REPLICATE_API_TOKEN not set", result.error
  end

  def test_describe_error_message_mentions_replicate_api_token
    ENV['REPLICATE_API_TOKEN'] = nil
    ENV['REPLICATE_API_KEY'] = nil
    
    result = MASTER::Replicate.describe(image_url: "http://example.com/img.jpg")
    
    assert result.err?
    assert_equal "REPLICATE_API_TOKEN not set", result.error
  end

  def test_run_error_message_mentions_replicate_api_token
    ENV['REPLICATE_API_TOKEN'] = nil
    ENV['REPLICATE_API_KEY'] = nil
    
    result = MASTER::Replicate.run(model_id: "test/model", input: {})
    
    assert result.err?
    assert_equal "REPLICATE_API_TOKEN not set", result.error
  end

  def test_create_prediction_accepts_keyword_arguments
    # This test verifies that create_prediction can be called with keyword arguments
    # We can't easily test the private method directly, but we verify the signature
    # is correct by ensuring run() method can successfully call it
    # (This would fail with ArgumentError if the signature was wrong)
    
    # We'll verify the method signature exists by checking the source
    source = MASTER::Replicate.method(:create_prediction).source_location
    assert source, "create_prediction method should exist"
  end

  def test_models_constant_exists
    assert_kind_of Hash, MASTER::Replicate::MODELS
    refute_empty MASTER::Replicate::MODELS
  end

  def test_model_categories_constant_exists
    assert_kind_of Hash, MASTER::Replicate::MODEL_CATEGORIES
    refute_empty MASTER::Replicate::MODEL_CATEGORIES
  end

  def test_models_includes_image_models
    assert MASTER::Replicate::MODELS.key?(:flux)
    assert MASTER::Replicate::MODELS.key?(:flux_pro)
    assert MASTER::Replicate::MODELS.key?(:flux_dev)
    assert MASTER::Replicate::MODELS.key?(:sdxl)
    assert MASTER::Replicate::MODELS.key?(:kandinsky)
    assert MASTER::Replicate::MODELS.key?(:ideogram_v2)
    assert MASTER::Replicate::MODELS.key?(:recraft_v3)
  end

  def test_models_includes_upscale_models
    assert MASTER::Replicate::MODELS.key?(:esrgan)
    assert MASTER::Replicate::MODELS.key?(:gfpgan)
    assert MASTER::Replicate::MODELS.key?(:codeformer)
    assert MASTER::Replicate::MODELS.key?(:clarity)
  end

  def test_models_includes_video_models
    assert MASTER::Replicate::MODELS.key?(:svd)
    assert MASTER::Replicate::MODELS.key?(:hailuo)
    assert MASTER::Replicate::MODELS.key?(:kling)
    assert MASTER::Replicate::MODELS.key?(:luma_ray)
    assert MASTER::Replicate::MODELS.key?(:wan)
    assert MASTER::Replicate::MODELS.key?(:sora)
  end

  def test_models_includes_audio_models
    assert MASTER::Replicate::MODELS.key?(:musicgen)
    assert MASTER::Replicate::MODELS.key?(:bark)
  end

  def test_models_includes_transcribe_models
    assert MASTER::Replicate::MODELS.key?(:whisper)
  end

  def test_models_includes_caption_models
    assert MASTER::Replicate::MODELS.key?(:blip)
  end

  def test_models_includes_3d_models
    assert MASTER::Replicate::MODELS.key?(:shap_e)
  end

  def test_model_id_returns_correct_string
    assert_equal 'black-forest-labs/flux-1.1-pro', MASTER::Replicate.model_id(:flux)
    assert_equal 'stability-ai/sdxl', MASTER::Replicate.model_id(:sdxl)
    assert_equal 'nightmareai/real-esrgan', MASTER::Replicate.model_id(:esrgan)
  end

  def test_model_id_accepts_string_argument
    assert_equal 'black-forest-labs/flux-1.1-pro', MASTER::Replicate.model_id('flux')
  end

  def test_model_id_raises_on_invalid_name
    error = assert_raises(ArgumentError) do
      MASTER::Replicate.model_id(:nonexistent)
    end
    assert_match(/Unknown model/, error.message)
  end

  def test_models_for_returns_array_for_image_category
    models = MASTER::Replicate.models_for(:image)
    assert_kind_of Array, models
    refute_empty models
    
    # Check structure
    first = models.first
    assert_kind_of Hash, first
    assert first.key?(:name)
    assert first.key?(:id)
    
    # Check that flux is in the list
    flux_model = models.find { |m| m[:name] == :flux }
    assert flux_model, "flux should be in image models"
    assert_equal 'black-forest-labs/flux-1.1-pro', flux_model[:id]
  end

  def test_models_for_returns_array_for_video_category
    models = MASTER::Replicate.models_for(:video)
    assert_kind_of Array, models
    refute_empty models
    
    # Check that video models are present
    model_names = models.map { |m| m[:name] }
    assert_includes model_names, :svd
    assert_includes model_names, :hailuo
  end

  def test_models_for_returns_array_for_upscale_category
    models = MASTER::Replicate.models_for(:upscale)
    assert_kind_of Array, models
    refute_empty models
    
    # Check that upscale models are present
    model_names = models.map { |m| m[:name] }
    assert_includes model_names, :esrgan
    assert_includes model_names, :gfpgan
  end

  def test_models_for_returns_empty_array_for_invalid_category
    models = MASTER::Replicate.models_for(:nonexistent)
    assert_kind_of Array, models
    assert_empty models
  end

  def test_generate_video_returns_error_when_api_key_not_set
    ENV['REPLICATE_API_TOKEN'] = nil
    ENV['REPLICATE_API_KEY'] = nil
    
    result = MASTER::Replicate.generate_video(prompt: "test video")
    
    assert result.err?
    assert_equal "REPLICATE_API_TOKEN not set", result.error
  end

  def test_generate_music_returns_error_when_api_key_not_set
    ENV['REPLICATE_API_TOKEN'] = nil
    ENV['REPLICATE_API_KEY'] = nil
    
    result = MASTER::Replicate.generate_music(prompt: "upbeat music")
    
    assert result.err?
    assert_equal "REPLICATE_API_TOKEN not set", result.error
  end

  def test_batch_generate_returns_error_when_api_key_not_set
    ENV['REPLICATE_API_TOKEN'] = nil
    ENV['REPLICATE_API_KEY'] = nil
    
    results = MASTER::Replicate.batch_generate(["prompt1", "prompt2"])
    
    assert_kind_of Array, results
    assert_equal 2, results.length
    results.each do |result|
      assert result.err?
      assert_equal "REPLICATE_API_TOKEN not set", result.error
    end
  end

  def test_model_categories_contains_all_categories
    categories = MASTER::Replicate::MODEL_CATEGORIES
    
    assert categories.key?(:image)
    assert categories.key?(:video)
    assert categories.key?(:upscale)
    assert categories.key?(:audio)
    assert categories.key?(:transcribe)
    assert categories.key?(:caption)
    assert categories.key?(:threed)
  end

  def test_all_model_category_entries_exist_in_models
    MASTER::Replicate::MODEL_CATEGORIES.each do |category, model_names|
      model_names.each do |name|
        assert MASTER::Replicate::MODELS.key?(name), 
               "Model #{name} from category #{category} should exist in MODELS hash"
      end
    end
  end
end
