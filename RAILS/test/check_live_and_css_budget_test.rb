# frozen_string_literal: true

require "minitest/autorun"
require "yaml"
require "tmpdir"
require "fileutils"
require "stringio"
require_relative "../../OPENBSD/lib/check_result"
require_relative "../../MASTER/checks/lib/source/css_constitution"
require_relative "../../MASTER/checks/lib/source/css_brace_balance"
require_relative "../../MASTER/checks/support/design_metrics"
require_relative "../../MASTER/checks/lib/research/design_metrics"
require_relative "../../MASTER/checks/support/css_weight"
require_relative "../../MASTER/lib/operator/checks"
require_relative "support/check_live_and_css_budget_sources"

# Two gaps, same shape: a rule that exists and measures nothing.
#
# CheckResult#measured_nothing? cannot express "ran fifty source checks, skipped
# every live one" -- the check count is non-zero, so the check passes and its skips
# are warnings. On 2026-08-03 that produced eight green checks on a machine with no
# app listening; booting them turned one red immediately.
#
# css_constitution defined IMPORTANT and never read it while 119 !important
# shipped; the 8px rhythm was checked only where the tokens are defined; and
# magic_color_hex_ban_inline had no reader at all.
class CheckLiveAndCssBudgetTest < Minitest::Test
  include CheckLiveAndCssBudgetSources

  def test_css_budget_failure_is_inconclusive
    source = File.read(File.expand_path("../../MASTER/checks/lib/source/css_constitution.rb", __dir__))
    assert_includes source, "CSS ceilings were not measured"
    assert_includes source, "@result.inconclusive!"
  end

  def test_a_skipped_live_check_is_a_warning_by_default
    result = result_with_skip

    assert_equal :passed, result.outcome
    assert_empty result.failures
    assert_equal 1, result.warnings.size
    refute result.conclusive?, "a live skip means not every declared check ran"

    stdout, = capture_io { result.render("design metrics passed") }
    assert_match(/design metrics passed \(50 check\(s\) ran, 1 live check\(s\) skipped\)/, stdout)
  end

  def test_require_live_turns_the_same_skip_into_a_failure
    ENV["CHECK_REQUIRE_LIVE"] = "1"
    result = result_with_skip

    assert_equal :failed, result.outcome
    assert_match(/live-required/, result.failures.first)
  end

  def test_require_live_is_off_unless_asked_for
    refute Deploy::CheckResult.require_live?({})
    assert Deploy::CheckResult.require_live?({ "CHECK_REQUIRE_LIVE" => "1" })
  end

  # The other half of the same gap, and the one that let a dead app read as green
  # without anybody setting a flag: a check whose ENTIRE check set is live-skipped
  # reported PASSED, because skipped_live files a warning rather than an unchecked
  # precondition, leaving both counts at zero. first_screen (then layout_geometry) said PASSED having
  # skipped all 17 of its checks.
  def test_a_check_that_skipped_every_live_check_measured_nothing
    result = Deploy::CheckResult.new
    result.skipped_live("amber port closed")
    result.skipped_live("bsdports port closed")

    assert_equal :inconclusive, result.outcome,
                 "a check that ran no checks at all must not report PASSED"
    assert result.measured_nothing?
    assert_match(/live check\(s\) skipped/, result.nothing_measured_reason)
  end

  # The distinction that keeps this from blocking normal VPS states: a parked amber
  # must not turn a check that measured brgen into a non-result.
  def test_a_check_that_measured_something_still_passes
    assert_equal :passed, result_with_skip.outcome
  end

  def test_a_composite_carries_its_leaves_live_skips
    leaf = Deploy::CheckResult.new
    leaf.skipped_live("brgen port closed")
    composite = Deploy::CheckResult.new.merge!(leaf, label: "geometry")

    assert_equal :inconclusive, composite.outcome,
                 "one leaf's skip count must reach the composite, or the suite claims " \
                 "coverage its leaves did not earn"
  end

  # "0 precondition(s) missing" was the old message for this case — true, and
  # useless: nothing was missing, nothing was listening.
  def test_the_reason_names_which_of_the_two_causes_it_was
    unchecked = Deploy::CheckResult.new.inconclusive!("no Chrome")
    live = Deploy::CheckResult.new
    live.skipped_live("port closed")

    assert_match(/precondition/, unchecked.nothing_measured_reason)
    refute_match(/precondition/, live.nothing_measured_reason)
  end

  def test_css_constitution_and_brace_checks_include_the_canonical_shared_engine
    shared = File.join(Deploy::CssConstitutionCheck::RAILS, "__shared", "app/assets/stylesheets/_tokens.scss")
    assert File.file?(shared), "the fixture is the mounted shared engine's source stylesheet"

    constitution = Deploy::CssConstitutionCheck.new.send(:css_files)
    braces = Deploy::CssBraceBalanceCheck.new.send(:css_files)
    design_metrics = Deploy::DesignMetricsCheck.new.send(:source_stylesheets)

    assert_includes constitution, shared
    assert_includes braces, shared
    assert_includes design_metrics, shared
  end

  def test_css_budget_failure_reports_all_sites_up_to_the_bounded_limit
    check = Deploy::CssConstitutionCheck.new
    check.instance_variable_set(:@result, Deploy::CheckResult.new)
    check.instance_variable_set(:@tally, { "type_scale" => Array.new(102) { |i| "fixture.scss:#{i + 1} 13px" } })
    check.define_singleton_method(:budgets) { { "type_scale" => 0 } }

    check.send(:judge_budgets)

    warnings = check.instance_variable_get(:@result).warnings
    assert_includes warnings, "css_constitution type_scale: fixture.scss:100 13px"
    assert_includes warnings, "css_constitution type_scale: 2 additional finding(s) omitted"
    refute warnings.any? { |line| line.include?("fixture.scss:101 13px") }
  end

  def test_every_counted_css_rule_has_a_ceiling
    check = Deploy::CssConstitutionCheck.run_once

    assert check.ok?, "css_constitution: #{check.failures.join(', ')}"
    %w[important rhythm magic_hex child_margin card_padding].each do |rule|
      assert_kind_of Integer, budget[rule], "#{rule} has no ceiling, so it checks nothing"
    end
  end
end
