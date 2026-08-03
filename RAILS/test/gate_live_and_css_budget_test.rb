# frozen_string_literal: true

require "minitest/autorun"
require "yaml"
require_relative "../../OPENBSD/lib/gate_result"
require_relative "../gates/lib/css_constitution"
require_relative "../gates/support/design_metrics"

# Two gaps, same shape: a rule that exists and measures nothing.
#
# GateResult#measured_nothing? cannot express "ran fifty source checks, skipped
# every live one" -- the check count is non-zero, so the gate passes and its skips
# are warnings. On 2026-08-03 that produced eight green gates on a machine with no
# app listening; booting them turned one red immediately.
#
# css_constitution defined IMPORTANT and never read it while 119 !important
# shipped; the 8px rhythm was checked only where the tokens are defined; and
# magic_color_hex_ban_inline had no reader at all.
class GateLiveAndCssBudgetTest < Minitest::Test
  def teardown
    ENV.delete("GATE_REQUIRE_LIVE")
  end

  def result_with_skip
    result = Deploy::GateResult.new
    result.checked!(50)
    result.skipped_live("brgen port 38182 closed")
    result
  end

  def test_a_skipped_live_check_is_a_warning_by_default
    result = result_with_skip

    assert_equal :passed, result.outcome
    assert_empty result.failures
    assert_equal 1, result.warnings.size
  end

  def test_require_live_turns_the_same_skip_into_a_failure
    ENV["GATE_REQUIRE_LIVE"] = "1"
    result = result_with_skip

    assert_equal :failed, result.outcome
    assert_match(/live-required/, result.failures.first)
  end

  def test_require_live_is_off_unless_asked_for
    refute Deploy::GateResult.require_live?({})
    assert Deploy::GateResult.require_live?({ "GATE_REQUIRE_LIVE" => "1" })
  end

  def budget
    YAML.safe_load_file(File.expand_path("../gates/data/css_budget.yml", __dir__)).fetch("rules")
  end

  def test_every_counted_css_rule_has_a_ceiling
    gate = Deploy::CssConstitutionGate.run_once

    assert gate.ok?, "css_constitution: #{gate.failures.join(', ')}"
    %w[important rhythm magic_hex].each do |rule|
      assert_kind_of Integer, budget[rule], "#{rule} has no ceiling, so it gates nothing"
    end
  end

  def test_contrast_ceilings_exist_for_both_bands
    assert_kind_of Integer, budget["contrast_below_aa"]
    assert_kind_of Integer, budget["contrast_below_aaa"]
  end

  # The vertical accents live in their own top-level map with no background of
  # their own, so token_pairs -- which pairs inside one dialect -- never saw them.
  def test_vertical_accents_are_paired_against_the_social_chrome
    tokens = YAML.safe_load_file(File.expand_path("../shared/design_tokens.yml", __dir__))
    pairs = Deploy::DesignMetrics.vertical_accent_pairs(tokens)

    refute_empty pairs
    labels = pairs.map { |pair| pair[:label] }

    assert_includes labels, "vertical_accents.marketplace_accent/social.bg"
    assert_includes labels, "vertical_accents.tv_accent/social.bg"
    marketplace = pairs.find { |pair| pair[:label] == "vertical_accents.marketplace_accent/social.bg" }

    assert_operator marketplace[:ratio], :<, 4.5, "the finding this pairing exists to surface has gone"
  end

  def test_danger_reads_as_a_foreground_token
    assert_match Deploy::DesignMetrics::FOREGROUND_KEY, "danger"
    assert_match Deploy::DesignMetrics::FOREGROUND_KEY, "dark_danger"
  end
end
