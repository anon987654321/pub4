# frozen_string_literal: true

require_relative "test_helper"

# The model phase of /fix, bounded: lanes probed before any file is sent, a
# wall-clock per file, lane failures remembered for the run, the worklist
# ranked easiest first, proposals that stray outside their finding refused, and
# a file dropped after two rejects. All with fake lanes; no model is asked.
class TestFixModelPhaseGuards < Minitest::Test
  Ledger = Master::Fix::RunLedger
  Probe = Master::Fix::LaneProbe

  def setup
    Ledger.reset!
    Master::Io::LaneQuota.clear_run_drops!
  end

  def teardown
    Ledger.reset!
    Master::Io::LaneQuota.clear_run_drops!
  end

  def test_the_probe_drops_slow_and_dead_lanes_for_the_run_and_keeps_the_fast_one
    fake = lambda do |model|
      case model
      when /\Afastlane/ then "OK"
      when /\Aslowlane/ then (sleep 2; "OK")
      else raise "connection refused"
      end
    end

    rows = Probe.run(models: %w[slowlane:a deadlane:a fastlane:a], ask: fake, budget: 0.3)

    assert_equal({ "fastlane" => :ok, "slowlane" => :slow, "deadlane" => :dead }, rows.to_h { |row| [row.lane, row.status] })
    assert_equal %w[deadlane slowlane], Master::Io::LaneQuota.run_drops.keys.sort
    assert_equal ["fastlane:a"], Master::Io::LaneSelection.order(%w[slowlane:a deadlane:a fastlane:a])
  end

  def test_an_empty_reply_is_not_a_live_lane
    rows = Probe.run(models: %w[mutelane:a], ask: ->(_) { "  " }, budget: 1)

    assert_equal :empty, rows.first.status
    assert Master::Io::LaneQuota.dead?("mutelane:a")
  end

  def test_a_lane_failing_twice_is_dropped_and_not_asked_again
    refute Ledger.lane_failed("flaky:model")
    assert Ledger.lane_failed("flaky:model")

    assert Master::Io::LaneQuota.dead?("flaky:other")
    refute Ledger.lane_failed("flaky:model"), "already dropped, not announced twice"
  end

  def test_a_file_stops_after_two_rejects_and_the_summary_counts_reasons
    refute Ledger.file_done?("a.rb")
    Ledger.reject("new_violations", file: "a.rb")
    Ledger.reject("out_of_scope", file: "a.rb")
    Ledger.reject("new_violations", file: "b.rb")

    assert Ledger.file_done?("a.rb")
    refute Ledger.file_done?("b.rb")
    assert_equal({ "new_violations" => 2, "out_of_scope" => 1 }, Ledger.reasons)
    assert_includes Ledger.summary_lines.first, "proposals rejected 3: new_violations 2, out_of_scope 1"
  end

  Loop = Struct.new(:law) # stands in for the loop's @law

  def budget_loop
    loop = Master::Fix::RepairLoop.allocate
    loop.instance_variable_set(:@law, Struct.new(:id).new("FEW_ARGUMENTS"))
    loop.instance_variable_set(:@root, "/r")
    loop.instance_variable_set(:@agent, Struct.new(:model).new("claude-cli:claude-sonnet-5-5"))
    loop
  end

  # "no_proposal" alone hid three different causes. Each is named, counted apart from
  # rejected proposals, and kept off the file's two-reject limit.
  def test_a_declined_call_names_its_reason_and_returns_nil
    assert_nil Ledger.declined("patch_rejected", file: "lib/a.rb", law: "X", detail: "1 out of 1 hunks failed")
    Ledger.declined("patch_rejected", file: "lib/b.rb")
    Ledger.declined("model_said_unchanged", file: "lib/c.rb")

    assert_equal({ "patch_rejected" => 2, "model_said_unchanged" => 1 }, Ledger.declined_reasons)
    refute Ledger.file_done?("lib/a.rb")
    assert_includes Ledger.summary_lines, "fix0: no proposal 3: patch_rejected 2, model_said_unchanged 1"
    assert_equal "patch_rejected 2, model_said_unchanged 1", Ledger.why_line
  end

  def test_the_why_line_merges_rejections_and_declined_calls_and_is_nil_when_empty
    assert_nil Ledger.why_line

    Ledger.reject("new_violations", file: "lib/a.rb")
    Ledger.declined("empty_reply", file: "lib/b.rb")

    assert_equal ["empty_reply 1", "new_violations 1"], Ledger.why_line.split(", ").sort
  end

  def test_a_file_that_outlasts_its_budget_is_skipped_and_recorded
    ENV["MASTER_FIX_FILE_BUDGET_S"] = "1"
    loop = budget_loop
    loop.send(:start_file_budget)

    result = loop.send(:within_file_budget, { file: "/r/slow.rb" }) { sleep 3 }
    loop.send(:start_file_budget)
    loop.send(:within_file_budget, { file: "/r/slow2.rb" }) { sleep 3 }

    assert_nil result
    assert loop.instance_variable_get(:@file_timed_out)
    assert_equal [["/r/slow.rb", 1], ["/r/slow2.rb", 1]], Ledger.timeouts
    refute Master::Io::LaneQuota.run_drops.key?("claude-cli"), "a slow file must not drop the lane"
  ensure
    ENV.delete("MASTER_FIX_FILE_BUDGET_S")
  end

  def test_a_fast_file_keeps_its_answer
    loop = budget_loop
    loop.send(:start_file_budget)

    assert_equal :done, loop.send(:within_file_budget, { file: "/r/a.rb" }) { :done }
    refute loop.instance_variable_get(:@file_timed_out)
  end

  def test_a_proposal_touching_lines_outside_its_finding_is_refused_before_the_verifier
    Dir.mktmpdir do |root|
      path = File.join(root, "a.rb")
      lines = (1..200).map { |n| "x#{n} = #{n}\n" }
      File.write(path, lines.join)
      loop = budget_loop

      near = lines.dup.tap { |l| l[9] = "x10 = :fixed\n" }.join
      far = lines.dup.tap { |l| l[150] = "x151 = :rewritten\n" }.join
      violation = { file: path, line: 10 }

      assert_nil loop.send(:outside_finding_range, violation, near)
      assert_match(/changes lines 151-151, finding range is 1-35/, loop.send(:outside_finding_range, violation, far))
      assert_nil loop.send(:outside_finding_range, { file: path, line: 0 }, far), "a whole-file finding is not range-checked"
    end
  end

  class Stream
    include Master::Fix::FixLoop::PassRunner::StreamStage
    def initialize = @root = "/r"
  end

  def test_the_worklist_is_easiest_first_and_max_files_hands_the_rest_to_the_rule_stage_as_handled
    rows = ->(n) { Array.new(n) { { law: "CQS" } } }
    ranked = [["/r/big.rb", rows.(5)], ["/r/small.rb", rows.(1)], ["/r/mid.rb", rows.(3)]]
    queue = Queue.new
    streamed = Set.new
    Ledger.max_files = 2

    Stream.new.send(:enqueue_ranked, ranked, queue, streamed)

    taken = Array.new(queue.size) { queue.pop.first }
    assert_equal %w[/r/small.rb /r/mid.rb], taken
    assert_equal [["big.rb", "CQS"]].to_set, streamed.map { |file, law| [File.basename(file), law] }.to_set
  end

  class Scanning < Stream
    attr_reader :scanned

    def initialize
      super
      @scanned = []
    end

    def violations_for(path)
      @scanned << path
      [{ law: "CQS", file: path }]
    end

    def resolve_violations(rows) = rows
  end

  def test_a_limited_run_stops_scanning_once_it_holds_its_files
    Ledger.max_files = 2
    scan = Scanning.new
    queue = Queue.new

    scan.send(:stream_violations, %w[/r/a.rb /r/b.rb /r/c.rb /r/d.rb], queue)

    assert_equal %w[/r/a.rb /r/b.rb], scan.scanned
    assert_equal 2, queue.size
  end

  def test_a_limited_run_does_not_wait_for_a_ranked_scan
    Ledger.max_files = 2

    refute Scanning.new.send(:rank_worklist?)
  end
end
