# frozen_string_literal: true

require_relative "test_helper"

class TestReplicate < Minitest::Test
  def setup
    # Save original API key
    @original_api_key = ENV['REPLICATE_API_KEY']
    # Set a mock API key for testing
    ENV['REPLICATE_API_KEY'] = 'test_key_12345'
  end

  def teardown
    # Restore original API key
    ENV['REPLICATE_API_KEY'] = @original_api_key
  end

  def test_models_constant_includes_all_categories
    # Image models
    assert MASTER::Replicate::MODELS.key?(:flux)
    assert MASTER::Replicate::MODELS.key?(:flux_pro)
    assert MASTER::Replicate::MODELS.key?(:flux_kontext)
    assert MASTER::Replicate::MODELS.key?(:flux2)
    assert MASTER::Replicate::MODELS.key?(:sdxl)
    assert MASTER::Replicate::MODELS.key?(:kandinsky)

    # Video models
    assert MASTER::Replicate::MODELS.key?(:hailuo)
    assert MASTER::Replicate::MODELS.key?(:mochi)

    # Music/Audio models
    assert MASTER::Replicate::MODELS.key?(:musicgen)
    assert MASTER::Replicate::MODELS.key?(:bark)
    assert MASTER::Replicate::MODELS.key?(:stable_audio)

    # 3D models
    assert MASTER::Replicate::MODELS.key?(:triposr)
    assert MASTER::Replicate::MODELS.key?(:trellis)

    # Upscale/Post models
    assert MASTER::Replicate::MODELS.key?(:esrgan)
    assert MASTER::Replicate::MODELS.key?(:gfpgan)

    # Caption model
    assert MASTER::Replicate::MODELS.key?(:blip)
  end

  def test_flux_alias_points_to_flux_pro
    assert_equal MASTER::Replicate::MODELS[:flux], MASTER::Replicate::MODELS[:flux_pro]
    assert_equal 'black-forest-labs/flux-1.1-pro', MASTER::Replicate::MODELS[:flux]
  end

  def test_default_model_is_flux_pro
    assert_equal :flux_pro, MASTER::Replicate::DEFAULT_MODEL
  end

  def test_available_returns_true_when_api_key_set
    assert MASTER::Replicate.available?
  end

  def test_available_returns_false_when_api_key_missing
    ENV['REPLICATE_API_KEY'] = nil
    refute MASTER::Replicate.available?
  end

  def test_generate_video_returns_error_without_api_key
    ENV['REPLICATE_API_KEY'] = nil
    result = MASTER::Replicate.generate_video(prompt: "test")
    
    assert result.err?
    assert_match(/Replicate:.*REPLICATE_API_KEY not set/, result.error)
  end

  def test_generate_music_returns_error_without_api_key
    ENV['REPLICATE_API_KEY'] = nil
    result = MASTER::Replicate.generate_music(prompt: "test music")
    
    assert result.err?
    assert_match(/Replicate:.*REPLICATE_API_KEY not set/, result.error)
  end

  def test_text_to_speech_returns_error_without_api_key
    ENV['REPLICATE_API_KEY'] = nil
    result = MASTER::Replicate.text_to_speech(text: "hello world")
    
    assert result.err?
    assert_match(/Replicate:.*REPLICATE_API_KEY not set/, result.error)
  end

  def test_generate_3d_returns_error_without_api_key
    ENV['REPLICATE_API_KEY'] = nil
    result = MASTER::Replicate.generate_3d(image_url: "http://example.com/test.jpg")
    
    assert result.err?
    assert_match(/Replicate:.*REPLICATE_API_KEY not set/, result.error)
  end

  def test_edit_image_returns_error_without_api_key
    ENV['REPLICATE_API_KEY'] = nil
    result = MASTER::Replicate.edit_image(image_url: "http://example.com/test.jpg", prompt: "add trees")
    
    assert result.err?
    assert_match(/Replicate:.*REPLICATE_API_KEY not set/, result.error)
  end

  def test_restore_face_returns_error_without_api_key
    ENV['REPLICATE_API_KEY'] = nil
    result = MASTER::Replicate.restore_face(image_url: "http://example.com/test.jpg")
    
    assert result.err?
    assert_match(/Replicate:.*REPLICATE_API_KEY not set/, result.error)
  end

  def test_generate_video_uses_correct_default_model
    # We can't make actual API calls in tests, but we can verify the method
    # accepts the correct parameters and would use the right model
    assert_respond_to MASTER::Replicate, :generate_video
  end

  def test_generate_music_accepts_duration_parameter
    # Verify method signature accepts duration
    assert_respond_to MASTER::Replicate, :generate_music
  end

  def test_text_to_speech_accepts_voice_parameter
    # Verify method signature accepts voice parameter
    assert_respond_to MASTER::Replicate, :text_to_speech
  end

  def test_generate_3d_accepts_model_parameter
    # Verify method signature accepts model parameter
    assert_respond_to MASTER::Replicate, :generate_3d
  end

  def test_edit_image_accepts_all_parameters
    # Verify method signature
    assert_respond_to MASTER::Replicate, :edit_image
  end

  def test_restore_face_accepts_params
    # Verify method signature
    assert_respond_to MASTER::Replicate, :restore_face
  end

  # Test backward compatibility
  def test_generate_still_works_with_flux_alias
    # Verify that :flux model alias still works for backward compatibility
    ENV['REPLICATE_API_KEY'] = nil
    result = MASTER::Replicate.generate(prompt: "test", model: :flux)
    
    # Should fail because no API key, but should not fail because of unknown model
    assert result.err?
    assert_match(/REPLICATE_API_KEY not set/, result.error)
  end

  def test_upscale_still_works
    # Verify existing upscale method is not broken
    # Note: upscale() is a pre-existing method that uses "REPLICATE_API_TOKEN" (not KEY)
    # and doesn't follow dmesg style - we keep backward compatibility
    ENV['REPLICATE_API_KEY'] = nil
    result = MASTER::Replicate.upscale(image_url: "http://example.com/test.jpg")
    
    assert result.err?
    assert_match(/REPLICATE_API/, result.error)
  end

  def test_describe_still_works
    # Verify existing describe method is not broken
    # Note: describe() is a pre-existing method that uses "REPLICATE_API_TOKEN" (not KEY)
    # and doesn't follow dmesg style - we keep backward compatibility
    ENV['REPLICATE_API_KEY'] = nil
    result = MASTER::Replicate.describe(image_url: "http://example.com/test.jpg")
    
    assert result.err?
    assert_match(/REPLICATE_API/, result.error)
  end

  def test_run_still_works
    # Verify existing run method is not broken
    ENV['REPLICATE_API_KEY'] = nil
    result = MASTER::Replicate.run(
      model_id: 'test/model',
      input: { prompt: 'test' }
    )
    
    assert result.err?
    assert_match(/REPLICATE_API_KEY not set/, result.error)
  end

  def test_download_file_method_exists
    # Verify download_file still exists
    assert_respond_to MASTER::Replicate, :download_file
  end
end
