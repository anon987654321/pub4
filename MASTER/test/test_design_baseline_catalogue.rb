# frozen_string_literal: true

require_relative "test_helper"
require "set"
require_relative "../tools/audit/design_baseline"

class TestDesignBaselineCatalogue < Minitest::Test
  Rule = Struct.new(:id)

  def test_stale_rule_ceiling_cannot_silently_lower_the_measured_baseline
    error = assert_raises(ArgumentError) do
      Operator::DesignBaseline.validate_rule_ceilings!(
        [Rule.new("KNOWN_RULE")],
        expected: Set["KNOWN_RULE", "REMOVED_RULE"],
      )
    end

    assert_match(/REMOVED_RULE/, error.message)
    assert_match(/missing or non-deterministic Laws/, error.message)
  end

  def test_known_deterministic_rule_ceilings_are_accepted
    assert Operator::DesignBaseline.validate_rule_ceilings!(
      [Rule.new("KNOWN_RULE")],
      expected: Set["KNOWN_RULE"],
    )
  end
end
