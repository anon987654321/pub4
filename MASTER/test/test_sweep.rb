# frozen_string_literal: true

require_relative "test_helper"
require_relative "../tools/sweep"

# The instruments existed and had no shared vocabulary: eight tools, eight
# ceiling files, eight invocations, and `bin/pub4 measure` aggregating the
# numbers but not the questions. This runs them as one pass per tree and reports
# in the dmesg form Trace::Dmesg and ThroughPipeline already use.
class TestSweep < Minitest::Test
  S = Pub4::Sweep

  def test_every_probe_names_a_real_tree
    unknown = S.probes.flat_map(&:trees).uniq - S::TREES

    assert_empty unknown
  end

  def test_every_probe_is_runnable
    S.probes.each do |probe|
      assert_respond_to probe.run, :call, "#{probe.unit} has no runner"
      arity = probe.scoped ? 1 : 0
      assert_equal arity, probe.run.arity, "#{probe.unit} scoped=#{probe.scoped.inspect} but takes #{probe.run.arity}"
    end
  end

  def test_probe_units_are_unique
    units = S.probes.map(&:unit)

    assert_equal units.uniq, units
  end

  # The bug this caught on its first honest run: design_baseline prints its
  # summary BEFORE its per-app detail, so "the last line is the verdict" reported
  # "shared: 1" as the verdict and hid "1 violation(s) (ceiling 0)" behind it.
  def test_the_verdict_is_the_summary_line_not_the_last_line
    body = ["design_baseline: 1 violation(s) (ceiling 0)", "  shared: 1 (ceiling -)"]

    assert_equal "1 violation(s) (ceiling 0)", S.verdict(body)
  end

  def test_the_verdict_falls_back_to_the_last_line
    assert_equal "no summary here", S.verdict(["  detail", "no summary here"])
  end

  # A census reported repo-wide under four tree headings is one fact wearing four
  # names. Scoped probes take the tree; unscoped ones say so by not taking it.
  def test_the_cohesion_probe_is_scoped
    assert S.probes.find { |p| p.unit == "cohesion" }.scoped
  end

  def test_repo_wide_probes_are_claimed_by_one_tree_only
    S.probes.reject(&:scoped).each do |probe|
      assert_equal 1, probe.trees.size,
                   "#{probe.unit} is unscoped, so listing it under #{probe.trees.size} trees prints the same number twice"
    end
  end

  def test_the_ledger_parses_and_every_row_is_shaped
    rows = S.ledger.fetch("proposals")

    refute_empty rows
    rows.each do |row|
      assert_includes %w[open landed refuted], row["state"], "#{row['id']} has state #{row['state'].inspect}"
      assert_includes S::TREES, row["tree"], "#{row['id']} names tree #{row['tree'].inspect}"
      refute_nil row["claim"], "#{row['id']} has no claim"
    end
  end

  # The point of the file. A loop that cannot say "tried it, wrong, here is why"
  # proposes the same thing every round and never plateaus.
  def test_every_refuted_row_carries_its_reason
    S.ledger.fetch("proposals").select { |r| r["state"] == "refuted" }.each do |row|
      refute_nil row["reason"], "#{row['id']} is refuted with no reason — the next round will re-propose it"
      refute_nil row["refuted_by"], "#{row['id']} names nothing that would catch it again"
    end
  end

  def test_every_landed_row_names_its_commit
    S.ledger.fetch("proposals").select { |r| r["state"] == "landed" }.each do |row|
      assert_match(/\A[0-9a-f]{7,40}\z/, row["landed_by"].to_s, "#{row['id']} landed without a commit")
    end
  end

  def test_proposal_ids_are_unique
    ids = S.ledger.fetch("proposals").map { |r| r["id"] }

    assert_equal ids.uniq, ids
  end
end
