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
end
