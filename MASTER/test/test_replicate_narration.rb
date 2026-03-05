# frozen_string_literal: true

require_relative "test_helper"

class TestReplicateNarration < Minitest::Test
  def setup
    @original_api_token = ENV['REPLICATE_API_TOKEN']
    @original_api_key = ENV['REPLICATE_API_KEY']
  end

  def teardown
    ENV['REPLICATE_API_TOKEN'] = @original_api_token
    ENV['REPLICATE_API_KEY'] = @original_api_key
  end

  def test_narration_script_returns_segments
    result = MASTER::Replicate::Narration.narration_script

    assert result.ok?
    assert result.value.key?(:segments)
    
    segments = result.value[:segments]
    assert_kind_of Array, segments
    refute_empty segments

    segment = segments.first
    assert segment.key?(:id)
    assert segment.key?(:text)
    assert segment.key?(:visual_prompt)
  end

  def test_narration_script_frozen
    segments = MASTER::Replicate::Narration::NARRATION_SEGMENTS

    assert segments.frozen?
    
    segments.each do |segment|
      assert segment.frozen?
    end
  end

  def test_generate_narration_requires_replicate
    ENV['REPLICATE_API_TOKEN'] = nil
    ENV['REPLICATE_API_KEY'] = nil

    result = MASTER::Replicate::Narration.generate_narration

    assert result.err?
    assert_equal "REPLICATE_API_TOKEN not set", result.error
  end

  def test_segments_count
    segments = MASTER::Replicate::Narration::NARRATION_SEGMENTS

    assert_equal 7, segments.length
    
    expected_ids = [:intro, :pipeline, :differentiator, :operations, :interface, :demo, :closing]
    actual_ids = segments.map { |s| s[:id] }
    
    assert_equal expected_ids, actual_ids
  end

  def test_segments_have_required_fields
    segments = MASTER::Replicate::Narration::NARRATION_SEGMENTS

    segments.each do |segment|
      refute_nil segment[:id], "Segment should have an id"
      refute_nil segment[:text], "Segment should have text"
      refute_nil segment[:visual_prompt], "Segment should have visual_prompt"
      
      assert_kind_of Symbol, segment[:id]
      assert_kind_of String, segment[:text]
      assert_kind_of String, segment[:visual_prompt]
      
      refute_empty segment[:text]
      refute_empty segment[:visual_prompt]
    end
  end
end
