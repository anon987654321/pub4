# frozen_string_literal: true

require "minitest/autorun"
require "yaml"
require_relative "../../OPENBSD/lib/gate_result"
require_relative "../gates/lib/source/css_constitution"
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
    result.skipped_live("brgen port closed")
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

  # The other half of the same gap, and the one that let a dead app read as green
  # without anybody setting a flag: a gate whose ENTIRE check set is live-skipped
  # reported PASSED, because skipped_live files a warning rather than an unchecked
  # precondition, leaving both counts at zero. first_screen (then layout_geometry) said PASSED having
  # skipped all 17 of its checks.
  def test_a_gate_that_skipped_every_live_check_measured_nothing
    result = Deploy::GateResult.new
    result.skipped_live("amber port closed")
    result.skipped_live("bsdports port closed")

    assert_equal :inconclusive, result.outcome,
                 "a gate that ran no checks at all must not report PASSED"
    assert result.measured_nothing?
    assert_match(/live check\(s\) skipped/, result.nothing_measured_reason)
  end

  # The distinction that keeps this from blocking normal VPS states: a parked amber
  # must not turn a gate that measured brgen into a non-result.
  def test_a_gate_that_measured_something_still_passes
    assert_equal :passed, result_with_skip.outcome
  end

  def test_a_composite_carries_its_leaves_live_skips
    leaf = Deploy::GateResult.new
    leaf.skipped_live("brgen port closed")
    composite = Deploy::GateResult.new.merge!(leaf, label: "geometry")

    assert_equal :inconclusive, composite.outcome,
                 "one leaf's skip count must reach the composite, or the suite claims " \
                 "coverage its leaves did not earn"
  end

  # "0 precondition(s) missing" was the old message for this case — true, and
  # useless: nothing was missing, nothing was listening.
  def test_the_reason_names_which_of_the_two_causes_it_was
    unchecked = Deploy::GateResult.new.inconclusive!("no Chrome")
    live = Deploy::GateResult.new
    live.skipped_live("port closed")

    assert_match(/precondition/, unchecked.nothing_measured_reason)
    refute_match(/precondition/, live.nothing_measured_reason)
  end

  def design_tokens
    YAML.safe_load_file(File.expand_path("../shared/design_tokens.yml", __dir__))
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

  def test_reduced_motion_overrides_are_not_important_debt
    gate = Deploy::CssConstitutionGate.new
    gate.run_once

    important = gate.tally.fetch("important")

    # Exempt: an !important inside a reduced-motion block, which is the pattern
    # there rather than a lapse. _canvas writes the media query and the
    # declarations on separate lines; _root writes the whole query on one. Both
    # are exempt, and by the same brace-depth mechanism — the one-liner sets
    # motion_depth before the tally check on that same line.
    refute_includes important, "brgen/app/assets/stylesheets/_canvas.scss:108"
    refute_includes important, "brgen/app/assets/stylesheets/_root.scss:123"

    # Not exempt: the rest of _root, whose focus-armor block is real !important
    # debt. Asserted as "some line in this file", because the previous version
    # named _root.scss:154 and line 154 has since become a comment — a pinned
    # line number turns any edit above it into a failure about nothing.
    assert(important.any? { |site| site.start_with?("brgen/app/assets/stylesheets/_root.scss:") },
           "the reduced-motion exemption has swallowed the whole file")
  end

  def test_reduced_motion_exception_stays_inside_its_media_block
    gate = Deploy::CssConstitutionGate.new
    gate.instance_variable_set(:@design, {})
    gate.instance_variable_set(:@tally, { "important" => [], "rhythm" => [], "magic_hex" => [], "type_scale" => [], "weight_ladder" => [] })

    gate.send(:count_budget_rules, "fixture.scss", "fixture.scss", <<~CSS)
      @media (prefers-reduced-motion: reduce) { .still { animation: none !important; } }
      .override { display: none !important; }
    CSS

    assert_equal ["fixture.scss:2"], gate.tally.fetch("important")
  end

  def test_contrast_ceilings_exist_for_both_bands
    assert_kind_of Integer, budget["contrast_below_aa"]
    assert_kind_of Integer, budget["contrast_below_aaa"]
  end

  # The vertical accents live in their own top-level map with no background of
  # their own, so token_pairs -- which pairs inside one dialect -- never saw them.
  #
  # The dialect they are paired against comes from the constant, not from a
  # literal here: it moved from "social" to "brgen_old_dark" at 9cefb0e02
  # ("design_metrics measured contrast on colours nothing paints") and this test
  # kept asserting the old label, so it had been failing on a rename rather than
  # on a measurement.
  def test_vertical_accents_are_paired_against_the_chrome_they_paint_on
    pairs = Deploy::DesignMetrics.vertical_accent_pairs(design_tokens)
    surface = Deploy::DesignMetrics::VERTICAL_SURFACE_DIALECT

    refute_empty pairs
    labels = pairs.map { |pair| pair[:label] }

    assert_includes labels, "vertical_accents.marketplace_accent/#{surface}.bg"
    assert_includes labels, "vertical_accents.tv_accent/#{surface}.bg"
  end

  # Not a specific colour: an accent that gets fixed should not fail this. What
  # must hold is that the pairing still surfaces something token_pairs missed,
  # which is the reason it was written. Today the hovers are what it catches.
  def test_the_vertical_pairing_still_surfaces_a_finding
    below_aa = Deploy::DesignMetrics.vertical_accent_pairs(design_tokens).select { |pair| pair[:ratio] < 4.5 }

    refute_empty below_aa, "every vertical accent now clears AA — retire this pairing or lower the bar deliberately"
    assert below_aa.all? { |pair| pair[:label].include?("_hover/") },
           "an accent, not just a hover, is below AA: #{below_aa.map { |pair| pair[:label] }.join(", ")}"
  end

  def test_danger_reads_as_a_foreground_token
    assert_match Deploy::DesignMetrics::FOREGROUND_KEY, "danger"
    assert_match Deploy::DesignMetrics::FOREGROUND_KEY, "dark_danger"
  end
end
