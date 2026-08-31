# frozen_string_literal: true

require_relative "test_helper"
require "yaml"
require "tmpdir"
require_relative "../tools/self_findings"

# The third census in this tree to record a bare integer, after data_reach and
# rule_audit. self_findings was 167 against a baseline of 154 and the number
# said nothing else, so attributing the overage meant checking out 01d5cc414 —
# the commit that set 154 — and diffing two full runs by hand. It came to eight
# rules, led by SAFE_NAVIGATION 0 -> 4 in a probe and NO_MULTIPLE_LANGUAGES
# 5 -> 7, and none of it needed to cost twenty minutes.
#
# So the baseline now carries per-rule counts beside the total, and an over run
# prints which rules moved. WISHLIST 65 asked for this in every census ratchet;
# this is the one where the detail already existed and was simply thrown away,
# since by_rule has always returned a rule => count hash.
class TestSelfFindingsDrift < Minitest::Test
  Tool = Pub4::SelfFindings

  def swap_ceiling(path)
    previous = Tool.const_get(:CEILING)
    Tool.send(:remove_const, :CEILING)
    Tool.const_set(:CEILING, path)
    yield
  ensure
    Tool.send(:remove_const, :CEILING)
    Tool.const_set(:CEILING, previous)
  end

  def with_baseline(contents)
    Dir.mktmpdir("self_findings") do |dir|
      path = File.join(dir, "self_findings.yml")
      File.write(path, contents.to_yaml)
      swap_ceiling(path) { yield }
    end
  end

  def test_the_total_is_still_read_from_findings
    with_baseline({ "findings" => 154 }) { assert_equal 154, Tool.ceiling }
  end

  def test_per_rule_counts_are_read_when_present
    with_baseline({ "findings" => 3, "by_rule" => { "GUARD_CLAUSE" => 2, "USE_THEN" => 1 } }) do
      assert_equal({ "GUARD_CLAUSE" => 2, "USE_THEN" => 1 }, Tool.recorded_by_rule)
    end
  end

  # The old format is a total and nothing else. It must keep working and must
  # say attribution is unavailable — "no rule moved" is a different claim and
  # the one thing it must not make.
  def test_a_total_only_baseline_says_attribution_is_unavailable
    with_baseline({ "findings" => 154 }) do
      assert_empty Tool.recorded_by_rule

      out, = capture_io { Tool.report_drift({ "GUARD_CLAUSE" => 28 }) }

      assert_match(/no by_rule recorded/, out)
      refute_match(/no rule moved/, out, "it claimed nothing moved when it could not know")
    end
  end

  def test_it_names_the_rules_that_moved_and_by_how_much
    with_baseline({ "findings" => 5, "by_rule" => { "GUARD_CLAUSE" => 27, "SAFE_NAVIGATION" => 0, "STEADY" => 4 } }) do
      out, = capture_io { Tool.report_drift({ "GUARD_CLAUSE" => 28, "SAFE_NAVIGATION" => 4, "STEADY" => 4 }) }

      assert_match(/GUARD_CLAUSE\s+27 ->\s+28\s+\+1/, out)
      assert_match(/SAFE_NAVIGATION\s+0 ->\s+4\s+\+4/, out)
      refute_match(/STEADY/, out, "a rule that did not move was reported as drift")
    end
  end

  def test_a_rule_that_disappeared_is_reported_too
    with_baseline({ "findings" => 2, "by_rule" => { "GONE" => 2 } }) do
      out, = capture_io { Tool.report_drift({}) }

      assert_match(/GONE\s+2 ->\s+0\s+-2/, out)
    end
  end

  def test_nothing_moving_says_so_when_the_baseline_is_known
    with_baseline({ "findings" => 1, "by_rule" => { "SAME" => 1 } }) do
      out, = capture_io { Tool.report_drift({ "SAME" => 1 }) }

      assert_match(/no rule moved/, out)
    end
  end
end
