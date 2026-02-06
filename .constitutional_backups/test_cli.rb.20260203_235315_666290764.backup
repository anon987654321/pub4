#!/usr/bin/env ruby
# frozen_string_literal: true

require "minitest/autorun"
require_relative "cli"

class TestScoreCalculator < Minitest::Test
  def test_perfect_score_with_no_violations
    assert_equal 100, Core::ScoreCalculator.calculate([])
  end

  def test_score_decreases_by_5_per_violation
    violations = [{"principle_id" => 1}]
    assert_equal 95, Core::ScoreCalculator.calculate(violations)
  end

  def test_score_floors_at_zero
    violations = Array.new(25) { {"principle_id" => 1} }
    assert_equal 0, Core::ScoreCalculator.calculate(violations)
  end

  def test_analyze_returns_breakdown
    violations = [
      {"severity" => "high", "auto_fixable" => true},
      {"severity" => "medium", "auto_fixable" => false},
      {"severity" => "high", "auto_fixable" => true}
    ]
    result = Core::ScoreCalculator.analyze(violations)

    assert_equal 3, result[:total]
    assert_equal 2, result[:by_severity]["high"]
    assert_equal 1, result[:by_severity]["medium"]
    assert_equal 2, result[:auto_fixable]
    assert_equal 85, result[:score]
  end
end

class TestTokenEstimator < Minitest::Test
  def test_estimate_ascii_text
    # ~4 chars per token for ASCII
    text = "hello world test"
    tokens = Core::TokenEstimator.estimate(text)
    assert_in_delta 4, tokens, 2
  end

  def test_warn_if_expensive_below_threshold
    result = Core::TokenEstimator.warn_if_expensive("short", 1000)
    assert_equal false, result[:warning]
  end

  def test_warn_if_expensive_above_threshold
    text = "x" * 10000
    result = Core::TokenEstimator.warn_if_expensive(text, 100)
    assert_equal true, result[:warning]
  end
end

class TestCostEstimator < Minitest::Test
  def test_fast_model_rates
    cost = Core::CostEstimator.estimate("qwen/qwen2.5-coder", 1000, 500)
    expected = (1000 * 0.1 / 1_000_000) + (500 * 0.3 / 1_000_000)
    assert_in_delta expected, cost, 0.0001
  end

  def test_claude_sonnet_rates
    cost = Core::CostEstimator.estimate("anthropic/claude-3.5-sonnet", 1000, 500)
    expected = (1000 * 3.0 / 1_000_000) + (500 * 15.0 / 1_000_000)
    assert_in_delta expected, cost, 0.0001
  end

  def test_claude_opus_rates
    cost = Core::CostEstimator.estimate("anthropic/claude-opus-4", 1000, 500)
    expected = (1000 * 15.0 / 1_000_000) + (500 * 75.0 / 1_000_000)
    assert_in_delta expected, cost, 0.0001
  end
end

class TestConvergenceDetector < Minitest::Test
  def test_no_loop_with_short_history
    history = [{violations: [1]}, {violations: [2]}]
    assert_equal false, Core::ConvergenceDetector.detect_loop(history)
  end

  def test_detects_loop_when_stuck
    history = [
      {violations: [{id: 1}]},
      {violations: [{id: 1}]},
      {violations: [{id: 1}]}
    ]
    assert_equal true, Core::ConvergenceDetector.detect_loop(history)
  end

  def test_no_loop_when_improving
    history = [
      {violations: [1, 2, 3]},
      {violations: [1, 2]},
      {violations: [1]}
    ]
    assert_equal false, Core::ConvergenceDetector.detect_loop(history)
  end

  def test_detects_oscillation
    history = [
      {violations: [{"principle_id" => 1}]},
      {violations: [{"principle_id" => 2}]},
      {violations: [{"principle_id" => 1}]},
      {violations: [{"principle_id" => 2}]}
    ]
    assert_equal true, Core::ConvergenceDetector.detect_oscillation(history)
  end

  def test_improving_with_decreasing_violations
    history = [
      {violations: [1, 2, 3]},
      {violations: [1, 2]},
      {violations: [1]}
    ]
    assert_equal true, Core::ConvergenceDetector.improving?(history)
  end
end

class TestLanguageDetector < Minitest::Test
  SUPPORTED = {
    "ruby" => {"extensions" => [".rb"], "indicators" => ["def ", "class "]},
    "python" => {"extensions" => [".py"], "indicators" => ["def ", "import "]},
    "javascript" => {"extensions" => [".js"], "indicators" => ["function ", "const "]}
  }.freeze

  def test_detect_by_extension
    assert_equal "ruby", Core::LanguageDetector.detect_by_extension("foo.rb", SUPPORTED)
    assert_equal "python", Core::LanguageDetector.detect_by_extension("bar.py", SUPPORTED)
    assert_equal "unknown", Core::LanguageDetector.detect_by_extension("baz.txt", SUPPORTED)
  end

  def test_detect_by_content
    ruby_code = "class Foo\n  def bar\n  end\nend"
    assert_equal "ruby", Core::LanguageDetector.detect_by_content(ruby_code, SUPPORTED)

    js_code = "const x = function() {}"
    assert_equal "javascript", Core::LanguageDetector.detect_by_content(js_code, SUPPORTED)
  end

  def test_detect_with_fallback
    # Extension takes precedence
    assert_equal "ruby", Core::LanguageDetector.detect_with_fallback("foo.rb", "const x", SUPPORTED)

    # Falls back to content when extension unknown
    assert_equal "ruby", Core::LanguageDetector.detect_with_fallback("foo.txt", "def bar", SUPPORTED)
  end
end

class TestLLMDetector < Minitest::Test
  def test_parse_violations_valid_json
    json = '[{"principle_id": 1, "line": 10}]'
    result = Core::LLMDetector.parse_violations(json)
    assert_equal 1, result.size
    assert_equal 1, result[0]["principle_id"]
  end

  def test_parse_violations_with_markdown_wrapper
    json = "```json\n[{\"principle_id\": 1}]\n```"
    result = Core::LLMDetector.parse_violations(json)
    assert_equal 1, result.size
  end

  def test_parse_violations_invalid_json_returns_empty
    result = Core::LLMDetector.parse_violations("not json")
    assert_equal [], result
  end

  def test_build_principle_summary
    principles = {
      "clarity" => {"id" => 1, "name" => "Clarity", "rule" => "Be clear", "priority" => 10, "smells" => ["vague"]}
    }
    summary = Core::LLMDetector.build_principle_summary(principles)

    assert_includes summary, "1. Clarity"
    assert_includes summary, "Priority 10"
    assert_includes summary, "vague"
  end
end

class TestPrincipleRegistry < Minitest::Test
  def setup
    @principles = {
      "clarity" => {"id" => 1, "name" => "Clarity", "priority" => 10, "smells" => ["vague"], "auto_fixable" => true},
      "simplicity" => {"id" => 2, "name" => "Simplicity", "priority" => 9, "smells" => ["complex"], "auto_fixable" => false}
    }
  end

  def test_find_by_id
    result = Core::PrincipleRegistry.find_by_id(@principles, 1)
    assert_equal "Clarity", result["name"]
  end

  def test_find_by_id_not_found
    result = Core::PrincipleRegistry.find_by_id(@principles, 999)
    assert_nil result
  end

  def test_find_by_smell
    result = Core::PrincipleRegistry.find_by_smell(@principles, "vague")
    assert_equal 1, result.size
    assert_equal "Clarity", result[0]["name"]
  end

  def test_auto_fixable
    result = Core::PrincipleRegistry.auto_fixable(@principles)
    assert_equal 1, result.size
    assert_equal "Clarity", result[0]["name"]
  end

  def test_max_priority
    assert_equal 10, Core::PrincipleRegistry.max_priority(@principles)
  end

  def test_validate_no_cycles_valid
    result = Core::PrincipleRegistry.validate_no_cycles(@principles)
    assert_equal true, result[:valid]
  end
end

class TestFileCleaner < Minitest::Test
  def setup
    @test_dir = File.join(Dir.tmpdir, "constitutional_test_#{$$}")
    FileUtils.mkdir_p(@test_dir)
  end

  def teardown
    FileUtils.rm_rf(@test_dir)
  end

  def test_text_file_detection
    assert Core::FileCleaner.text_file?("foo.rb")
    assert Core::FileCleaner.text_file?("bar.py")
    assert Core::FileCleaner.text_file?("baz.md")
    refute Core::FileCleaner.text_file?("image.png")
    refute Core::FileCleaner.text_file?("binary.exe")
  end

  def test_clean_removes_trailing_whitespace
    file = File.join(@test_dir, "test.rb")
    File.write(file, "hello   \nworld  \n")

    Core::FileCleaner.clean(file)

    assert_equal "hello\nworld\n", File.read(file)
  end

  def test_clean_removes_carriage_returns
    file = File.join(@test_dir, "test.rb")
    File.write(file, "hello\r\nworld\r\n")

    Core::FileCleaner.clean(file)

    assert_equal "hello\nworld\n", File.read(file)
  end

  def test_clean_collapses_blank_lines
    file = File.join(@test_dir, "test.rb")
    File.write(file, "hello\n\n\n\nworld\n")

    Core::FileCleaner.clean(file)

    assert_equal "hello\n\nworld\n", File.read(file)
  end
end

class TestResult < Minitest::Test
  def test_ok_result
    result = Result.ok(42)
    assert result.ok?
    assert_equal 42, result.value
    assert_nil result.error
  end

  def test_err_result
    result = Result.err("something went wrong")
    refute result.ok?
    assert_nil result.value
    assert_equal "something went wrong", result.error
  end
end

class TestDmesg < Minitest::Test
  def test_version_defined
    assert_match(/\d+\.\d+/, Dmesg::VERSION)
  end

  def test_color_disabled_with_no_color_env
    original = ENV["NO_COLOR"]
    ENV["NO_COLOR"] = "1"

    refute Dmesg.color_enabled?
  ensure
    ENV["NO_COLOR"] = original
  end

  def test_icon_fallback_with_no_color
    original = ENV["NO_COLOR"]
    ENV["NO_COLOR"] = "1"

    assert_equal "[dir]", Dmesg.icon(:folder)
    assert_equal "[clean]", Dmesg.icon(:clean)
  ensure
    ENV["NO_COLOR"] = original
  end
end

# Run tests if executed directly
if __FILE__ == $PROGRAM_NAME
  # Suppress bootstrap output during tests
  Options.quiet = true
end
