# frozen_string_literal: true

require_relative "test_helper"

class TestReachToolCoverage < Minitest::Test
  TIERS = %i[safe open guarded dangerous].freeze

  def test_every_registered_reach_tool_has_a_valid_tier
    classes = Master::Io.constants.filter_map do |constant|
      candidate = Master::Io.const_get(constant)
      candidate if candidate.is_a?(Class) && candidate.const_defined?(:NAME, false)
    end
    refute_empty classes
    missing_tier = classes.reject { |klass| klass.const_defined?(:TIER, false) }
    assert_empty missing_tier.map(&:name), "reach tools missing TIER"

    invalid = classes.reject { |klass| TIERS.include?(klass.const_get(:TIER)) }
    assert_empty invalid.map(&:name), "reach tools have invalid TIER"
  end
end
