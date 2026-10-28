# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "stringio"
require_relative "../tools/gap_discipline"

# The known-bad rule, applied to the gap discipline: every check here has
# already caught a broken fixture in a temp tree before it is allowed to
# judge the real one. The green fixture at the end is the minimum shape the
# real data must keep.
class TestGapDiscipline < Minitest::Test
  GOOD_LEDGER = {
    "gaps" => [
      { "id" => "app_x_feature", "app" => "app_x", "kind" => "logic", "name" => "feature", "status" => "picked", "workstream" => "ws_feature" },
      { "id" => "app_x_other", "app" => "app_x", "kind" => "ux", "name" => "other", "status" => "open" },
    ],
  }.freeze

  GOOD_RECORD = {
    "app" => "app_x",
    "gaps" => %w[app_x_feature app_x_other],
    "candidates" => [
      { "id" => "x1", "gap" => "app_x_feature", "spec" => "a", "hyperlocal" => "low", "synergy" => "low", "cost" => "S", "laws_delta" => "none", "reversibility" => "high" },
      { "id" => "x2", "gap" => "app_x_feature", "spec" => "b", "hyperlocal" => "low", "synergy" => "low", "cost" => "S", "laws_delta" => "none", "reversibility" => "high" },
      { "id" => "x3", "gap" => "app_x_feature", "spec" => "c", "hyperlocal" => "low", "synergy" => "low", "cost" => "S", "laws_delta" => "none", "reversibility" => "high" },
      { "id" => "x4", "gap" => "app_x_other", "spec" => "d", "hyperlocal" => "low", "synergy" => "low", "cost" => "S", "laws_delta" => "none", "reversibility" => "high" },
      { "id" => "x5", "gap" => "app_x_other", "spec" => "e", "hyperlocal" => "low", "synergy" => "low", "cost" => "S", "laws_delta" => "none", "reversibility" => "high" },
      { "id" => "x6", "gap" => "app_x_other", "spec" => "f", "hyperlocal" => "low", "synergy" => "low", "cost" => "S", "laws_delta" => "none", "reversibility" => "high" },
      { "id" => "x7", "gap" => "app_x_other", "spec" => "g", "hyperlocal" => "low", "synergy" => "low", "cost" => "S", "laws_delta" => "none", "reversibility" => "high" },
      { "id" => "x8", "gap" => "app_x_other", "spec" => "h", "hyperlocal" => "low", "synergy" => "low", "cost" => "S", "laws_delta" => "none", "reversibility" => "high" },
      { "id" => "x9", "gap" => "app_x_other", "spec" => "i", "hyperlocal" => "low", "synergy" => "low", "cost" => "S", "laws_delta" => "none", "reversibility" => "high" },
      { "id" => "x10", "gap" => "app_x_other", "spec" => "j", "hyperlocal" => "low", "synergy" => "low", "cost" => "S", "laws_delta" => "none", "reversibility" => "high" },
    ],
    "critique" => [
      { "candidate" => "x1", "verdict" => "reject", "attack" => "why" },
      { "candidate" => "x2", "verdict" => "reject", "attack" => "why" },
      { "candidate" => "x3", "verdict" => "keep", "attack" => "why" },
      { "candidate" => "x4", "verdict" => "keep", "attack" => "why" },
      { "candidate" => "x5", "verdict" => "reject", "attack" => "why" },
      { "candidate" => "x6", "verdict" => "reject", "attack" => "why" },
      { "candidate" => "x7", "verdict" => "reject", "attack" => "why" },
      { "candidate" => "x8", "verdict" => "reject", "attack" => "why" },
      { "candidate" => "x9", "verdict" => "reject", "attack" => "why" },
      { "candidate" => "x10", "verdict" => "reject", "attack" => "why" },
    ],
    "picks" => [
      { "gap" => "app_x_feature", "winner" => "x3", "rationale" => "why" },
      { "gap" => "app_x_other", "winner" => "x4", "rationale" => "why" },
    ],
  }.freeze

  GOOD_CONVERGENCE = {
    "workstreams" => [ { "id" => "ws_feature", "state" => "partial", "title" => "Feature", "implementation" => "somewhere", "proof" => "somewhere" } ],
  }.freeze

  def setup
    @dir = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(@dir, "data", "ideations"))
    write("data/gaps.yml", GOOD_LEDGER)
    write("data/ideations/app_x.yml", GOOD_RECORD)
    write("convergence.yml", GOOD_CONVERGENCE)
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def write(rel, object)
    File.write(File.join(@dir, rel), object.to_yaml)
  end

  # Plain-Ruby deep copy: this test runs without ActiveSupport, so no
  # deep_dup. Marshal round-trip is enough for YAML-shaped fixtures.
  def copy(object)
    Marshal.load(Marshal.dump(object))
  end

  def run_check
    io = StringIO.new
    ok = Deploy::GapDiscipline.run(root: @dir, io:)
    [ ok, io.string ]
  end

  def test_green_fixture_passes
    ok, out = run_check

    assert ok, out
    assert_includes out, "CLEAN"
  end

  def test_winner_rejected_by_critique_is_caught
    record = copy(GOOD_RECORD)
    record["picks"][0]["winner"] = "x1" # critique rejected x1
    write("data/ideations/app_x.yml", record)

    ok, out = run_check

    refute ok
    assert_includes out, "whom critique did not keep"
  end

  def test_gap_with_too_few_candidates_is_caught
    record = copy(GOOD_RECORD)
    record["candidates"].reject! { |c| %w[x2 x3].include?(c["id"]) }
    record["critique"].reject! { |c| %w[x2 x3].include?(c["candidate"]) }
    write("data/ideations/app_x.yml", record)

    ok, out = run_check

    refute ok
    assert_includes out, "has 1 candidates, needs 3"
  end

  def test_missing_axis_is_caught
    record = copy(GOOD_RECORD)
    record["candidates"].first.delete("reversibility")
    write("data/ideations/app_x.yml", record)

    ok, out = run_check

    refute ok
    assert_includes out, "missing axis reversibility"
  end

  def test_pick_of_a_candidate_from_another_gap_is_caught
    record = copy(GOOD_RECORD)
    record["picks"][0]["winner"] = "x4" # a real candidate — of the other gap
    write("data/ideations/app_x.yml", record)

    ok, out = run_check

    refute ok
    assert_includes out, "not a candidate of that gap"
  end

  def test_picked_ledger_row_without_workstream_is_caught
    ledger = copy(GOOD_LEDGER)
    ledger["gaps"].first.delete("workstream")
    write("data/gaps.yml", ledger)

    ok, out = run_check

    refute ok
    assert_includes out, "without a workstream row"
  end

  def test_picked_ledger_row_with_unknown_workstream_is_caught
    ledger = copy(GOOD_LEDGER)
    ledger["gaps"].first["workstream"] = "ws_ghost"
    write("data/gaps.yml", ledger)

    ok, out = run_check

    refute ok
    assert_includes out, "workstream ws_ghost not found"
  end

  def test_unparseable_data_fails_rather_than_passes
    File.write(File.join(@dir, "data", "gaps.yml"), "gaps: [unclosed")

    ok, out = run_check

    refute ok
    assert_includes out, "unparseable"
  end
end
