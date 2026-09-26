# frozen_string_literal: true

require "minitest/autorun"
require "yaml"
require_relative "../../OPENBSD/lib/gate_result"
require_relative "../../MASTER/gates/lib/source/css_constitution"
require_relative "../../MASTER/gates/support/design_metrics"
require_relative "../../MASTER/gates/lib/research/design_metrics"
require_relative "../../MASTER/gates/support/css_weight"
require_relative "../../MASTER/lib/operator/gates"

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

  def test_css_budget_failure_is_inconclusive
    source = File.read(File.expand_path("../../MASTER/gates/lib/source/css_constitution.rb", __dir__))
    assert_includes source, "CSS ceilings were not measured"
    assert_includes source, "@result.inconclusive!"
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
    Operator::MasterDesign.design_system
  end

  def budget
    YAML.safe_load_file(File.expand_path("../../MASTER/gates/data/css_budget.yml", __dir__)).fetch("rules")
  end

  def test_every_counted_css_rule_has_a_ceiling
    gate = Deploy::CssConstitutionGate.run_once

    assert gate.ok?, "css_constitution: #{gate.failures.join(', ')}"
    %w[important rhythm magic_hex child_margin card_padding].each do |rule|
      assert_kind_of Integer, budget[rule], "#{rule} has no ceiling, so it gates nothing"
    end
  end

  # Exempt: an !important inside a reduced-motion block, which is the pattern
  # there rather than a lapse. Not exempt: every other !important in the same
  # stylesheet, such as the wordmark's armor, which is real debt.
  #
  # The sites are found by the rule they sit in rather than pinned by line. Two
  # pinned lines stood here and both had drifted onto lines carrying no
  # !important at all, so the exempt half asserted nothing while it passed.
  def test_reduced_motion_overrides_are_not_important_debt
    gate = Deploy::CssConstitutionGate.new
    gate.run_once
    important = gate.tally.fetch("important")

    rel = "brgen/app/assets/stylesheets/application.scss"
    source = File.read(File.join(Deploy::CssConstitutionGate::RAILS, rel))
    motion, rest = Operator::ScssRules.rules(source).reject(&:at_rule?)
                                      .partition { |rule| rule.parents.any? { |parent| parent.include?("prefers-reduced-motion") } }
    sites = lambda do |rules|
      rules.flat_map do |rule|
        (rule.line..rule.end_line).select { |n| source.lines[n - 1].include?("!important") }.map { |n| "#{rel}:#{n}" }
      end
    end

    refute_empty sites.call(motion), "no reduced-motion override carries !important, so this proves nothing"
    assert_empty sites.call(motion) & important
    refute_empty sites.call(rest) & important, "the reduced-motion exemption has swallowed the whole file"
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

  # The rhythm budget, planted both ways: an off-rhythm px is counted, and the
  # same number in a line comment, a block comment's continuation line, or a
  # token fallback is not.
  def test_an_off_rhythm_px_is_counted_and_a_commented_one_is_not
    gate = rhythm_gate
    gate.send(:count_budget_rules, "fixture.scss", "fixture.scss", <<~CSS)
      .card { padding: 13px; }
      .card { margin-top: -16px; gap: 24px; }
      // .old { padding: 13px; }
      /* The previous rule
         read padding: 13px here. */
      .tap { min-height: calc(var(--tap-min, 13px) + 4px); padding: var(--space-3, 13px); }
    CSS

    assert_equal ["fixture.scss:1 13px"], gate.tally.fetch("rhythm")
  end

  def test_rhythm_over_its_ceiling_fails_the_gate
    gate = rhythm_gate
    gate.instance_variable_set(:@result, Deploy::GateResult.new)
    gate.instance_variable_set(:@budgets, { "rhythm" => 0 })
    gate.send(:count_budget_rules, "fixture.scss", "fixture.scss", ".card { padding: 13px; }\n")
    gate.send(:judge_budgets)
    result = gate.instance_variable_get(:@result)

    assert_includes result.failures, "css_constitution rhythm: 1 exceeds ceiling 0 (+1) — fix them, or record a new ceiling with a reason"
  end

  def rhythm_gate
    gate = Deploy::CssConstitutionGate.new
    gate.instance_variable_set(:@design, Operator::MasterDesign.blocks(Deploy::CssConstitutionGate::MASTER_DESIGN))
    gate.instance_variable_set(:@tally, { "important" => [], "rhythm" => [], "magic_hex" => [], "type_scale" => [], "weight_ladder" => [] })
    gate
  end

  def test_contrast_ceilings_exist_for_both_bands
    assert_kind_of Integer, budget["contrast_below_aa"]
    assert_kind_of Integer, budget["contrast_below_aaa"]
  end

  # The ceilings existing in the YAML and the gate reaching them are two facts,
  # and only the first was asserted. Every budget reader here rescues and runs
  # unbudgeted, so a path that stops resolving costs the ceiling and leaves the
  # gate green — which is what a file move did to design_metrics twice, the
  # second time on 2026-09-08 despite a comment in the file warning about the
  # first. A reader that returns nothing is the failure; assert what it returns.
  def test_every_budget_reader_reaches_its_file
    readers = {
      "design_metrics contrast" => Deploy::DesignMetricsGate.new.send(:contrast_budget),
      "css_constitution rules" => Deploy::CssConstitutionGate.new.send(:budgets),
      "css_constitution weight" => Deploy::CssConstitutionGate.new.send(:weight_ceilings),
      "constitutional_scan targets" => Deploy::ConstitutionalScanGate.new.send(:budget)
    }

    readers.each do |name, values|
      refute_empty values, "#{name}: budget unreadable, so the gate runs unbudgeted and still reports ok"
    end
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
  #
  # Called the way DesignMetricsGate calls it. The hover pairs are the accent ink
  # on the hover fill, and the ink is read from the stylesheets under the RAILS
  # root, so without the root there are no hover pairs to find.
  def test_the_vertical_pairing_still_surfaces_a_finding
    pairs = Deploy::DesignMetrics.vertical_accent_pairs(design_tokens, Deploy::DesignMetricsGate::RAILS)
    below_aa = pairs.select { |pair| pair[:ratio] < 4.5 }

    refute_empty below_aa, "every vertical accent now clears AA — retire this pairing or lower the bar deliberately"
    assert below_aa.all? { |pair| pair[:bg_key].end_with?("_hover") },
           "an accent, not just a hover, is below AA: #{below_aa.map { |pair| pair[:label] }.join(", ")}"
  end

  def test_danger_reads_as_a_foreground_token
    assert_match Deploy::DesignMetrics::FOREGROUND_KEY, "danger"
    assert_match Deploy::DesignMetrics::FOREGROUND_KEY, "dark_danger"
  end

  def spacing_gate
    gate = Deploy::CssConstitutionGate.new
    gate.instance_variable_set(:@tally, {
      "important" => [], "rhythm" => [], "magic_hex" => [],
      "type_scale" => [], "weight_ladder" => [],
      "child_margin" => [], "card_padding" => []
    })
    gate
  end

  def test_a_child_combinator_with_a_nonzero_margin_is_gap_over_margin_debt
    gate = spacing_gate
    gate.send(:scan_spacing, "fixture.scss", <<~CSS)
      .stack > * { margin-bottom: 8px; }
      .stack > * { margin: 0; }
      .stack { margin-bottom: 8px; }
    CSS

    assert_equal [ "fixture.scss:1" ], gate.tally.fetch("child_margin")
  end

  def test_card_padding_other_than_24px_is_counted
    gate = spacing_gate
    gate.send(:scan_spacing, "fixture.scss", <<~CSS)
      .card { padding: 1rem; }
      .card { padding: 1.5rem; }
      .card { padding: var(--space-6); }
      .card-grid { padding: 8px; }
    CSS

    assert_equal [ "fixture.scss:1 1rem" ], gate.tally.fetch("card_padding")
  end

  def test_a_line_height_literal_is_counted_and_a_leading_token_is_not
    gate = spacing_gate
    gate.instance_variable_set(:@design, {})
    gate.send(:count_budget_rules, "fixture.scss", "fixture.scss", <<~CSS)
      .a { line-height: 1.5; }
      .b { line-height: var(--leading-normal); }
      .c { line-height: normal; }
      .d { font-size: 14px; line-height: 20px; }
    CSS

    assert_equal [ "fixture.scss:1 1.5", "fixture.scss:4 20px" ], gate.tally.fetch("leading")
  end
end
