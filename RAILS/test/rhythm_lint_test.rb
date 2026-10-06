# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../MASTER/tools/rhythm_lint"

class RhythmLintTest < Minitest::Test
  LINT = Operator::RhythmLint

  def test_missing_constitutional_rules_are_not_clean
    LINT.stub(:load_design_rules, nil) do
      refute LINT.run, "missing MASTER/data/laws.yml must fail the measurement"
    end
  end

  def test_missing_rhythm_rule_is_not_clean
    LINT.stub(:load_design_rules, { "pixel_perfection" => {} }) do
      refute LINT.run, "missing eight_px_rhythm must fail the measurement"
    end
  end

  def test_live_rhythm_configuration_is_present
    rules = LINT.load_design_rules
    refute_nil rules
    refute_empty rules.fetch("pixel_perfection").fetch("eight_px_rhythm")
  end
end
