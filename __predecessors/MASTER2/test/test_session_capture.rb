# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../lib/master"

class TestSessionCapture < Minitest::Test
  def setup
    @test_var_dir = Dir.mktmpdir
    MASTER::Paths.instance_variable_set(:@var, @test_var_dir)
    @capture_file = File.join(@test_var_dir, "session_captures.jsonl")
  end

  def teardown
    FileUtils.rm_rf(@test_var_dir) if @test_var_dir && Dir.exist?(@test_var_dir)
  end

  def test_capture_file_path
    expected = File.join(@test_var_dir, "session_captures.jsonl")
    assert_equal expected, MASTER::SessionCapture.capture_file
  end

  def test_questions_defined
    assert_equal 5, MASTER::SessionCapture::QUESTIONS.size
    
    categories = MASTER::SessionCapture::QUESTIONS.map { |q| q[:category] }
    assert_includes categories, :technique
    assert_includes categories, :pattern
    assert_includes categories, :question
    assert_includes categories, :automation
    assert_includes categories, :tool
  end

  def test_review_no_captures
    result = MASTER::SessionCapture.review
    assert result.err?
    assert_match /No captures found/, result.error
  end

  def test_review_with_captures
    # Create a test capture
    capture_entry = {
      session_id: "test-123",
      timestamp: Time.now.utc.iso8601,
      answers: { technique: "test technique" }
    }
    
    File.open(@capture_file, "w") do |f|
      f.puts(JSON.generate(capture_entry))
    end

    result = MASTER::SessionCapture.review
    assert result.ok?
    assert_equal 1, result.value[:count]
    assert_equal 1, result.value[:captures].size
  end

  def test_suggest_automations
    # Create test captures with automation suggestions
    capture1 = {
      session_id: "test-1",
      timestamp: Time.now.utc.iso8601,
      answers: { automation: "automate refactoring" }
    }
    capture2 = {
      session_id: "test-2",
      timestamp: Time.now.utc.iso8601,
      answers: { technique: "no automation here" }
    }
    
    File.open(@capture_file, "w") do |f|
      f.puts(JSON.generate(capture1))
      f.puts(JSON.generate(capture2))
    end

    result = MASTER::SessionCapture.suggest_automations
    assert result.ok?
    assert_equal 1, result.value[:suggestions].size
    assert_equal "automate refactoring", result.value[:suggestions].first
  end

  def test_map_to_learning_category
    # Test private method via public interface
    mapping = {
      technique: :good_practice,
      pattern: :bug_pattern,
      question: :ux_insight,
      automation: :architecture,
      tool: :architecture
    }

    mapping.each do |capture_cat, expected_learning_cat|
      result = MASTER::SessionCapture.send(:map_to_learning_category, capture_cat)
      assert_equal expected_learning_cat, result, 
        "Expected #{capture_cat} to map to #{expected_learning_cat}"
    end
  end

  def test_auto_capture_without_successful_flag
    session = MASTER::Session.current
    # Don't set successful flag
    
    # Should return early without capturing
    result = MASTER::SessionCapture.auto_capture_if_successful
    assert_nil result
  end
end
