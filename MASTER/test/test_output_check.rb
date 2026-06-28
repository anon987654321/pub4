# frozen_string_literal: true

require_relative "test_helper"

class TestOutputCheck < Minitest::Test
  def rules
    {
      "schema" => 1,
      "hallucination" => ["i (?:created|added|wrote) `[^`]+\\.rb`"],
      "hedge_violation" => ["\\bwill probably\\b"],
      "refusal_failure_unhelpful" => ["as an ai language model"],
    }
  end

  def check = Master::Judge::OutputCheck.new(rules)

  def test_detects_error_and_warning_categories
    errors = check.check("I created `lib/imaginary.rb`.")
    warnings = check.check("This will probably work.")

    assert_equal :error, errors.first.severity
    assert_equal :warning, warnings.first.severity
  end

  def test_unhelpful_refusal_is_blocking
    assert check.blocking?("As an AI language model, no.")
  end

  def test_schema_metadata_is_not_compiled_as_a_pattern
    assert_empty check.check("A clean answer.")
  end

  def test_empty_input_is_clean
    assert_empty check.check("")
    assert_empty check.check(nil)
  end

  def test_invalid_regex_does_not_crash
    checker = Master::Judge::OutputCheck.new("hallucination" => ["[unclosed"])
    assert_empty checker.check("anything")
  end
end
