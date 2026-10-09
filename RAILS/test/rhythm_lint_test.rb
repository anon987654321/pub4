# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../MASTER/tools/rhythm_lint"

class RhythmLintTest < Minitest::Test
  LINT = Operator::RhythmLint

  def test_missing_constitutional_rules_are_not_clean
    with_design_rules(nil) do
      refute LINT.run, "missing MASTER/data/laws.yml must fail the measurement"
    end
  end

  def test_missing_rhythm_rule_is_not_clean
    with_design_rules({ "scale" => {} }) do
      refute LINT.run, "missing scale.space_px must fail the measurement"
    end
  end

  def test_live_rhythm_configuration_is_present
    rules = LINT.load_design_rules
    refute_nil rules
    refute_empty rules.fetch("scale").fetch("space_px")
  end

  private

  def with_design_rules(value)
    singleton = LINT.singleton_class
    singleton.send(:alias_method, :__load_design_rules_before_test, :load_design_rules)
    singleton.send(:define_method, :load_design_rules) { value }
    yield
  ensure
    singleton.send(:remove_method, :load_design_rules)
    singleton.send(:alias_method, :load_design_rules, :__load_design_rules_before_test)
    singleton.send(:remove_method, :__load_design_rules_before_test)
  end
end
