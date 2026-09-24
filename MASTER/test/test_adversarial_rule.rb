# frozen_string_literal: true

require_relative "test_helper"
# The rule classes are reached by explicit require, not by autoload: a plural
# *_rules.rb holds several *Rule classes here, so no constant matches the file
# name and Zeitwerk has nothing to resolve. test_scan_rule_contracts requires
# its file for the same reason. Without this the whole case errored in setup on
# uninitialized constant, which is a test that cannot run rather than one that
# passes — it reported 0 assertions and read as green in a summary line.
require "review/scan/rules/semantic_rules"

class TestAdversarialRule < Minitest::Test
  def setup
    @rule = Master::Review::Scan::Rules::AdversarialRule.new
  end

  def test_responds_to_check
    assert_respond_to @rule, :check
  end

  def test_returns_array
    result = @rule.check("def foo; end", path: "foo.rb")
    assert_kind_of Array, result
  end

  # The file is in the prompt, so the call is made with tools withheld, and
  # the withholding ends with the call.
  def test_the_model_call_is_made_without_tools
    seen = nil
    agent = Object.new
    agent.define_singleton_method(:ask) do |_prompt, operation:|
      seen = [operation, Fiber[:master_no_tools]]
      "ISSUE:1:unused method"
    end
    rule = Master::Review::Scan::Rules::AdversarialRule.new(agent:)

    findings = rule.check("def foo; end", path: "foo.rb")

    assert_equal [:scan_adversarial, true], seen
    assert_equal 1, findings.size
    assert_nil Fiber[:master_no_tools]
  end
end
