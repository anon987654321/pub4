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

  # The second population, added 2026-09-06. The row above called itself "what
  # our own rules find in our own trees" and counted the law alone, so nothing
  # counted the 145 rules the scanner builds. Both baselines live in one file,
  # the registry's under a prefix, so every reader here is the same reader with
  # an argument.
  def test_the_registry_total_is_read_from_its_own_key
    with_baseline({ "findings" => 151, "registry_findings" => 108 }) do
      assert_equal 108, Tool.registry_ceiling
      assert_equal 151, Tool.ceiling, "the registry key displaced the law's"
    end
  end

  def test_registry_attribution_is_read_from_the_prefixed_keys
    baseline = { "findings" => 1, "by_rule" => { "GUARD_CLAUSE" => 1 },
                 "registry_findings" => 2, "registry_by_rule" => { "SILENT_RESCUE" => 2 },
                 "registry_finding_members" => ["SILENT_RESCUE a.rb:1", "SILENT_RESCUE b.rb:2"] }
    with_baseline(baseline) do
      assert_equal({ "SILENT_RESCUE" => 2 }, Tool.recorded_by_rule("registry"))
      assert_equal 2, Tool.recorded_members("registry").size
      assert_equal({ "GUARD_CLAUSE" => 1 }, Tool.recorded_by_rule)
      assert_empty Tool.recorded_members
    end
  end

  # A ratchet run rewrites this file, and most of it is prose recording what
  # each past move cost somebody. The dup_census ceiling lost thirty lines of
  # history to a bare to_yaml dump; this is the assertion that keeps it.
  def test_recording_keeps_the_prose_and_writes_both_populations
    Dir.mktmpdir("self_findings") do |dir|
      path = File.join(dir, "self_findings.yml")
      File.write(path, "---\n# why the number is what it is\nfindings: 9\nby_rule:\n  OLD: 9\n")
      swap_ceiling(path) do
        Tool.stub(:members, ["GUARD_CLAUSE a.rb:1"]) do
          Tool.stub(:registry_members, ["SILENT_RESCUE b.rb:2"]) do
            File.write(path, Tool.rewritten_ceiling)
          end
        end
      end

      written = File.read(path)
      recorded = YAML.safe_load(written)

      assert_includes written, "# why the number is what it is"
      assert_equal 1, recorded["findings"]
      assert_equal 1, recorded["registry_findings"]
      assert_equal({ "SILENT_RESCUE" => 1 }, recorded["registry_by_rule"])
      assert_equal ["SILENT_RESCUE b.rb:2"], recorded["registry_finding_members"]
      refute_includes recorded.keys, "OLD"
    end
  end

  # The two rows must not count the same finding twice. A law reaches the
  # scanner through LawBridgeRule and reports under its own id, so a registry
  # census that kept those ids would move both ratchets on one fix — fifteen
  # findings on the day the row was written. Asserted against the recorded
  # baseline rather than a live scan, which is a minute of measurement.
  def test_the_two_populations_share_no_rule
    law_ids = Tool.law.keys.map(&:to_s)
    registry_ids = Tool.recorded_by_rule("registry").keys

    refute_empty registry_ids, "the registry baseline records no rules"
    assert_empty registry_ids & law_ids,
                 "a law's findings are counted in both rows; one fix would move two ratchets"
  end
end
