# frozen_string_literal: true

require_relative "test_helper"

# The model phase of /fix, bounded: lanes probed before any file is sent, a
# wall-clock per file, lane failures remembered for the run, an impact-ranked
# worklist, proposals that stray outside their finding refused, and a file
# dropped after two rejects. All with fake lanes; no model is asked.
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

  # The run's summary names the errors it caught and carried on past, the busiest place first.
  def test_the_summary_names_the_errors_the_run_swallowed
    crash = { "context" => "RepairLoop.reflexion", "error_class" => "Encoding::CompatibilityError",
              "error_message" => "incompatible" }
    rows = [crash, crash, { "context" => "lane", "error_class" => "NoMethodError", "error_message" => "nil" }]

    lines = Master::Ground::Swallow.stub(:recent, rows) { Ledger.summary_lines }

    assert_includes lines, "fix0: errors swallowed this run 3 at 2 place(s)"
    assert_includes lines, "fix0: swallowed 2x at RepairLoop.reflexion: Encoding::CompatibilityError: incompatible"
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

  # A refusal feeds the next attempt once: it is kept per thread, read once, and shows in the
  # prompt only inside the retry.
  def test_a_refusal_note_reaches_only_the_retry_prompt
    assert_equal "", Ledger.retry_note
    Ledger.refused_because("changes lines 26-80, finding range is 20-40")

    assert_equal "changes lines 26-80, finding range is 20-40", Ledger.take_refusal
    assert_nil Ledger.take_refusal
    Ledger.retrying("too wide") { assert_includes Ledger.retry_note, "Your previous proposal was refused: too wide" }
    assert_equal "", Ledger.retry_note
  end

  def retry_loop(outcomes)
    loop = Master::Fix::RepairLoop.allocate
    loop.instance_variable_set(:@law, Struct.new(:id).new("TEST_LAW"))
    seen = []
    loop.define_singleton_method(:attempt_fix) do |_violation|
      seen << Master::Fix::RunLedger.retry_note
      Master::Fix::RunLedger.refused_because("lines 1-9 are outside 4-6") if seen.size == 1
      outcomes.shift
    end
    [loop, seen]
  end

  def test_a_refused_repair_is_retried_once_with_the_reason
    loop, seen = retry_loop(%i[out_of_scope applied])

    out, = capture_io { assert_equal :applied, loop.send(:fix_violation, { file: "lib/a.rb", law: "X" }) }

    assert_equal 2, seen.size
    assert_equal "", seen.first
    assert_includes seen.last, "lines 1-9 are outside 4-6"
    assert_includes out, "fix0: retrying a.rb TEST_LAW once, told: lines 1-9 are outside 4-6"
  end

  def test_a_second_refusal_is_final_and_a_non_refusal_is_never_retried
    loop, seen = retry_loop(%i[out_of_scope out_of_scope])
    capture_io { assert_equal :out_of_scope, loop.send(:fix_violation, { file: "lib/a.rb" }) }
    assert_equal 2, seen.size

    loop, seen = retry_loop(%i[no_proposal])
    assert_equal :no_proposal, loop.send(:fix_violation, { file: "lib/a.rb" })
    assert_equal 1, seen.size
  end

  def test_the_retry_switch_turns_the_second_try_off
    loop, seen = retry_loop(%i[out_of_scope applied])
    previous = ENV["MASTER_FIX_RETRY"]
    ENV["MASTER_FIX_RETRY"] = "0"
    begin
      assert_equal :out_of_scope, loop.send(:fix_violation, { file: "lib/a.rb" })
    ensure
      previous ? ENV["MASTER_FIX_RETRY"] = previous : ENV.delete("MASTER_FIX_RETRY")
    end

    assert_equal 1, seen.size
  end

  # A pass cut short by a hot reload attempted nothing; calling the run completed was a pass
  # reported over work that never ran.
  def test_only_a_done_terminal_state_reports_completed
    loop = Master::Fix::FixLoop.allocate
    done = Master::Result.ok("DONE: clean")
    plateau = Master::Result.ok("PLATEAU: pass limit reached")
    human = Master::Result.ok("HUMAN_DECISION: approval required")
    inconclusive = Master::Result.err("semantic evidence unavailable", category: :inconclusive)

    Master::Fix::CodeWatch.stub(:requested?, false) do
      assert_equal "completed", loop.send(:run_end_reason, done)
      assert_match(/\Aplateau:/, loop.send(:run_end_reason, plateau))
      assert_match(/\Ahuman_decision:/, loop.send(:run_end_reason, human))
      assert_match(/\Ainconclusive:/, loop.send(:run_end_reason, inconclusive))
    end

    # A pass cut short by a hot reload attempted nothing; calling it completed
    # would claim work that never ran.
    Master::Fix::CodeWatch.stub(:requested?, true) do
      assert_match(/\Areloading/, loop.send(:run_end_reason, done))
    end
  end

  def test_a_rejection_names_what_it_introduced
    out, = capture_io { Ledger.reject("higher_priority_violation", file: "lib/a.rb", law: "X", detail: "DENSITY line 12") }

    assert_includes out, "fix0: proposal rejected, lib/a.rb X: higher_priority_violation (DENSITY line 12)"
    capture_io { Ledger.reject("new_violations", file: "lib/b.rb") }
    assert_equal 2, Ledger.reasons.values.sum
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

  # A repair is a proposal, a retry after a patch that did not apply, and a verifier call: three or four
  # model calls of twenty to sixty seconds. The budget has to hold them, and MASTER_FIX_FILE_BUDGET_S overrides it.
  def test_the_default_file_budget_holds_a_repair_with_a_retry_and_the_environment_overrides_it
    ENV.delete("MASTER_FIX_FILE_BUDGET_S")

    assert_operator Ledger.file_budget_s, :>=, 4 * 60

    ENV["MASTER_FIX_FILE_BUDGET_S"] = "7"

    assert_equal 7, Ledger.file_budget_s
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

  # A signature change edits its callers wherever they are; a small hunk at a
  # call of the method is in scope, and a rewrite elsewhere still is not.
  def test_a_signature_change_may_reach_its_call_sites_and_nothing_else
    Dir.mktmpdir do |root|
      path = File.join(root, "a.rb")
      lines = ["def resize(width, height, depth, unit)\n", "  [width, height, depth, unit]\n", "end\n"]
      lines += (4..120).map { |n| "x#{n} = #{n}\n" }
      lines[99] = "box = resize(1, 2, 3, :cm)\n"
      File.write(path, lines.join)

      loop = budget_loop
      violation = { file: path, line: 1 }

      signature = lines.dup
      signature[0] = "def resize(size)\n"
      signature[1] = "  size.values_at(:width, :height, :depth, :unit)\n"
      signature[99] = "box = resize(width: 1, height: 2, depth: 3, unit: :cm)\n"
      assert_nil loop.send(:outside_finding_range, violation, signature.join)

      unrelated = signature.dup
      unrelated[109] = "x110 = :rewritten\n"
      assert_match(/changes lines 110-110/, loop.send(:outside_finding_range, violation, unrelated.join))
    end
  end

  class Stream
    include Master::Fix::FixLoop::PassRunner::StreamStage
    def initialize = @root = "/r"
  end

  def test_the_worklist_prioritizes_severity_and_hands_deferred_files_to_the_rule_stage
    rows = ->(law, severity, n) { Array.new(n) { { law:, severity: } } }
    ranked = [
      ["/r/big.rb", rows.call("CQS", :warning, 5)],
      ["/r/small.rb", rows.call("NO_PUTS", :info, 1)],
      ["/r/mid.rb", rows.call("ROBUSTNESS", :error, 2)],
    ]
    queue = Queue.new
    streamed = Set.new
    Ledger.max_files = 2

    Stream.new.send(:enqueue_ranked, ranked, queue, streamed)

    taken = Array.new(queue.size) { queue.pop.first }
    assert_equal %w[/r/mid.rb /r/big.rb], taken
    assert_equal [["small.rb", "NO_PUTS"]].to_set,
                 streamed.map { |file, law| [File.basename(file), law] }.to_set
  end

  def test_a_later_high_severity_law_finding_is_not_starved_by_the_batch_cap
    low_priority = Array.new(Master::Fix::FixLoop::PassRunner::StreamStage::LAW_CAP) do
      { law: "LONG_LINE", severity: :warning }
    end
    urgent = [{ law: "LONG_LINE", severity: :error }]
    queue = Queue.new

    Stream.new.send(:enqueue_ranked, [["/r/early.rb", low_priority], ["/r/urgent.rb", urgent]], queue, Set.new)

    assert_equal 2, queue.size
    path, rows = queue.pop
    assert_equal "/r/urgent.rb", path
    assert_equal :error, rows.first[:severity]
    deferred_path, deferred_rows = queue.pop
    assert_equal "/r/early.rb", deferred_path
    assert_equal Master::Fix::FixLoop::PassRunner::StreamStage::LAW_CAP - 1, deferred_rows.size
  end

  def test_an_unbounded_worklist_ranks_in_rolling_batches_by_default
    previous = ENV["MASTER_FIX_RANK"]
    previous_limit = ENV["MASTER_FIX_MAX_FILES"]
    ENV.delete("MASTER_FIX_RANK")
    ENV.delete("MASTER_FIX_MAX_FILES")
    Ledger.reset!

    assert Stream.new.send(:rank_worklist?)
    assert_equal 20, Stream.new.send(:rank_window), "unbounded scans rank in bounded windows to start repairs early"
  ensure
    previous ? ENV["MASTER_FIX_RANK"] = previous : ENV.delete("MASTER_FIX_RANK")
    previous_limit ? ENV["MASTER_FIX_MAX_FILES"] = previous_limit : ENV.delete("MASTER_FIX_MAX_FILES")
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

  def test_an_unbounded_default_scan_collects_the_corpus_before_queueing_repairs
    previous = ENV["MASTER_FIX_RANK"]
    previous_limit = ENV["MASTER_FIX_MAX_FILES"]
    ENV.delete("MASTER_FIX_RANK")
    ENV.delete("MASTER_FIX_MAX_FILES")
    Ledger.reset!
    scan = Scanning.new
    paths = %w[/r/a.rb /r/b.rb /r/c.rb /r/d.rb]
    queue = Queue.new

    scan.send(:stream_violations, paths, queue)

    assert_equal paths, scan.scanned
    assert_equal paths.size, queue.size
  ensure
    previous ? ENV["MASTER_FIX_RANK"] = previous : ENV.delete("MASTER_FIX_RANK")
    previous_limit ? ENV["MASTER_FIX_MAX_FILES"] = previous_limit : ENV.delete("MASTER_FIX_MAX_FILES")
  end

  # Ranks in batches of two and records how many files were already queued as each file is read.
  class Windowed < Scanning
    attr_reader :queued_at_read, :stream_stopped_at

    def initialize
      super
      @queued_at_read = []
    end

    def scan(files, queue, deadline: nil)
      @queue = queue
      stream_violations(files, queue, deadline:)
    end

    def rank_window = 2
    def rank_worklist? = true

    def violations_for(path)
      @queued_at_read << @queue.size
      super
    end
  end

  def test_an_unbounded_scan_queues_repairs_before_it_finishes
    queue = Queue.new
    scan = Windowed.new

    scan.scan(%w[/r/a.rb /r/b.rb /r/c.rb /r/d.rb], queue)

    assert_equal [0, 0, 2, 2], scan.queued_at_read, "the first batch was queued while the scan went on"
    assert_equal 4, queue.size
  end

  def test_the_scan_stops_at_the_run_deadline
    scan = Windowed.new

    scan.scan(%w[/r/a.rb /r/b.rb], Queue.new, deadline: Time.at(0))

    assert_empty scan.scanned
    assert_equal "/r/a.rb", scan.stream_stopped_at
  end

def test_a_stopping_run_scans_no_further
  scan = Windowed.new

  Master::Fix::RunBudget.stub(:stopping, "stalled, pass 1") do
    scan.scan(%w[/r/a.rb /r/b.rb], Queue.new)
  end

  assert_empty scan.scanned
  assert_equal "/r/a.rb", scan.stream_stopped_at
end

  def test_one_law_repairs_at_most_the_cap_per_ranked_batch
    cap = Master::Fix::FixLoop::PassRunner::StreamStage::LawCap.new(2, Hash.new(0))
    rows = Array.new(3) { { law: "LONG_LINE" } } + [{ law: "CQS" }]

    taken = cap.take(rows)

    assert_equal %w[LONG_LINE LONG_LINE CQS], taken.map { |row| row[:law] }
  end

  def test_a_limited_run_does_not_wait_for_a_ranked_scan
    previous = ENV["MASTER_FIX_RANK"]
    ENV.delete("MASTER_FIX_RANK")
    Ledger.max_files = 2

    refute Scanning.new.send(:rank_worklist?)
  ensure
    previous ? ENV["MASTER_FIX_RANK"] = previous : ENV.delete("MASTER_FIX_RANK")
  end
end
