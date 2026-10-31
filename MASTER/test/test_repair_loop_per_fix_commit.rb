# frozen_string_literal: true

require_relative "test_helper"

# One fix, one commit, one push — before the next violation is touched. And the
# two guards that keep a per-fix pipeline honest: a proposal that collapses a
# file (the 2026-09-17 UNCHANGED corruption) never reaches the write, and a
# fix that leaves a new violation on the lines it changed is not a repair.
class TestRepairLoopPerFixCommit < Minitest::Test
  Rule = Struct.new(:id, :severity)

  class FakeBus
    attr_reader :events

    def initialize
      @events = []
    end

    def publish(event, payload = {})
      @events << [event, payload]
    end
  end

  class RecordingScanner
    def scan(path, laws: nil)
      source = File.read(path)
      findings = Array.new(source.scan("violation").size) do |index|
        { law: "TEST_RULE", severity: :warning, line: index + 1, message: "fix me" }
      end
      Master::Result.ok(findings)
    end
  end

  # Answers one finding list for the before-scan and another for the after, so
  # a fix can land with a violation the old content did not carry.
  class SequenceScanner
    def initialize(before, after)
      @answers = [before, after]
    end

    def scan(_path, laws: nil)
      Master::Result.ok(@answers.size > 1 ? @answers.shift : @answers.first)
    end
  end

  class FixingAgent
    def ask(_prompt)
      "```ruby\nclean\n```"
    end

    def ask_once(_prompt, **)
      "SAFE"
    end
  end

  class FakeCommitter
    attr_reader :calls

    def initialize(fail: false)
      @calls = []
      @fail = fail
    end

    def commit_if_dirty(message, findings: [], owned_paths: nil)
      raise "pre-commit hook refused" if @fail

      @calls << [message, findings, owned_paths]
    end

    # The loop attests the content it wrote before it commits it.
    def attest_written!(*paths)
      (@attested ||= []).concat(paths.flatten)
    end

    def attested = @attested.to_a
  end

  def build_loop(root:, bus:, scanner:, agent:, committer: nil)
    loop = Master::Fix::RepairLoop.new(
      law: Rule.new("TEST_RULE", :warning),
      agent:,
      scanner:,
      root:,
      bus:,
      committer:,
    )
    # The genetic strategy waits RATE_LIMIT_SLEEP between candidate attempts,
    # which is a lane's cost, not this file's subject — a stub keeps the
    # per-fix commit tests from sleeping 30s apiece.
    loop.define_singleton_method(:wait_before_retry) { |*_args| }
    loop
  end

  def violation_in(path)
    Master::Fix::Violation.from_finding(
      { law: "TEST_RULE", severity: :warning, line: 1, message: "fix me" },
      file: path, ext: ".rb",
    )
  end

  # The sentinel half of the collapse guard: the refusal spellings, and not
  # the words a real file can wear.
  def test_collapse_guard_sentinels
    guard = Master::Fix::RepairLoop::CollapseGuard
    assert guard.sentinel?("UNCHANGED")
    assert guard.sentinel?("unchanged\n")
    assert guard.sentinel?("No changes")
    assert guard.sentinel?("  SAFE  ")
    # A whole file can be the word clean; it must not read as a refusal.
    refute guard.sentinel?("clean")
    refute guard.sentinel?("puts 1")
    refute guard.sentinel?("")
  end

  def test_collapse_guard_shrink_ratio_and_deletion_exempt
    guard = Master::Fix::RepairLoop::CollapseGuard
    big = "x" * 1_000
    collapse = lambda do |law, old_src, new_src|
      guard.collapse(Master::Fix::ChangeScope.between(old_src, new_src), law:, proposal: new_src)
    end

    assert_equal "the proposal is 10% of the file's 1000 bytes, under the 40% floor",
                 collapse.call("TRAILING_COMMAS", big, "x" * 100)
    assert_nil collapse.call("TRAILING_COMMAS", big, "x" * 600)
    # A DEAD_CODE fix may legitimately gut a file.
    assert_nil collapse.call("DEAD_CODE", big, "x")
    # An empty file has nothing to collapse against.
    assert_nil collapse.call("ANY_RULE", "", "x")
    assert_match(/refusal word "UNCHANGED"/, collapse.call("DEAD_CODE", big, "UNCHANGED"))
  end

  # A proposal that keeps most of the file but stubs a body with a marker
  # passes the shrink floor; the elision half catches it. A marker the file
  # already had is the file's own text, not the lane stopping.
  def test_collapse_guard_refuses_new_elision_markers
    guard = Master::Fix::RepairLoop::CollapseGuard
    old_src = ["def a", "  1", "end", "", "def b", "  2", "end", ""].join("\n")
    stubbed = ["def a", "  1", "end", "", "def b", "  ... rest of the method unchanged", "end", ""].join("\n")

    assert_match(/elides instead of writing the file \(6: \.\.\. rest/, guard.collapse(
      Master::Fix::ChangeScope.between(old_src, stubbed), law: "TRAILING_COMMAS", proposal: stubbed, original: old_src,
    ))
    ["[truncated]", "<!-- continued"].each { |marker| assert guard.elisions("a\n#{marker}\n", "a\n").any?, marker }
    assert_empty guard.elisions(stubbed, stubbed)
    assert_empty guard.elisions(["value = rest_of_items", "the rest of the logic is below", ""].join("\n"), "")
  end

  # The 2026-09-17 RAILS run wrote the literal word UNCHANGED over a live view.
  # The re-scan approved it, because one word holds no violations — no
  # instrument downstream of the write can catch this one.
  def test_apply_rejects_a_proposal_that_collapses_the_file
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.erb")
      File.write(path, "line\n" * 40)
      bus = FakeBus.new
      loop = build_loop(root:, bus:, scanner: RecordingScanner.new, agent: FixingAgent.new)

      refute loop.send(:apply, path, "UNCHANGED", violation_in(path))
      assert_equal "line\n" * 40, File.read(path)
      rejected = bus.events.find { |event, _| event == "repair_loop:fix_rejected" }
      assert_equal "collapsed_content", rejected&.last&.fetch(:reason)
    end
  end

  class RaisingAfterWriteScanner
    def initialize = @calls = 0
    def scan(_path, **)
      @calls += 1
      raise "scanner died" if @calls > 1

      Master::Result.ok([])
    end
  end

  def test_apply_restores_the_original_when_a_step_after_the_write_raises
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "violation\n")
      bus = FakeBus.new
      loop = build_loop(root:, bus:, scanner: RaisingAfterWriteScanner.new, agent: FixingAgent.new)

      refute loop.send(:apply, path, "model wrote this\n", violation_in(path))
      assert_equal "violation\n", File.read(path)
      rejected = bus.events.find { |event, _| event == "repair_loop:fix_rejected" }
      assert_equal "exception", rejected&.last&.fetch(:reason)
    end
  end

  # The fence could carry the refusal too: extract_code tested only the bare
  # spelling, so "```html\nUNCHANGED\n```" passed as file content.
  def test_extract_code_refuses_a_fenced_sentinel
    Dir.mktmpdir do |root|
      loop = build_loop(root:, bus: FakeBus.new, scanner: RecordingScanner.new, agent: FixingAgent.new)

      assert_nil loop.send(:extract_code, "```html\nUNCHANGED\n```", ".html")
      assert_nil loop.send(:extract_code, "UNCHANGED", ".html")
      assert_equal "puts 1\n", loop.send(:extract_code, "```ruby\nputs 1\n```", ".rb")
    end
  end

  # Boyscout, line-scoped: the fix touched line 1 and left a violation there
  # that the old content did not carry. The file's total did not grow, so the
  # count check passed — this is the check that catches the swap.
  def test_apply_rejects_a_new_violation_on_a_touched_line
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "violation\n")
      bus = FakeBus.new
      before = [{ law: "TEST_RULE", severity: :warning, line: 1, message: "fix me" }]
      after = [{ law: "NEW_RULE", severity: :warning, line: 1, message: "left behind" }]
      loop = build_loop(root:, bus:, scanner: SequenceScanner.new(before, after), agent: FixingAgent.new)

      refute loop.send(:apply, path, "clean but wrong\n", violation_in(path))
      assert_equal "violation\n", File.read(path)
      rejected = bus.events.find { |event, _| event == "repair_loop:fix_rejected" }
      assert_equal "boyscout_violation", rejected&.last&.fetch(:reason)
      assert_equal "1 more: NEW_RULE line 1", rejected.last.fetch(:introduced)
    end
  end

  # A refactor that eases a finding changes its message ("ABC size 43" to
  # "ABC size 31"); matched by message, that read as a new finding and the
  # repair was refused. The rule's count did not grow, so nothing landed.
  def test_a_finding_whose_numbers_changed_is_not_new
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "violation\n")
      before = [{ law: "ABC_SIZE", severity: :warning, line: 1, message: "ABC size 43.0 for #build" },
                { law: "TEST_RULE", severity: :warning, line: 1, message: "fix me" }]
      after = [{ law: "ABC_SIZE", severity: :warning, line: 1, message: "ABC size 31.0 for #build" }]
      loop = build_loop(root:, bus: FakeBus.new, scanner: SequenceScanner.new(before, after), agent: FixingAgent.new)

      assert loop.send(:apply, path, "eased\n", violation_in(path))
    end
  end

  # A signature change edits its def and a caller far below it. Judged as one span, every finding
  # between the two was the repair's; judged by hunk, a line it never touched is not.
  def test_a_finding_between_two_hunks_is_not_the_repairs
    Dir.mktmpdir do |root|
      path, proposed = two_hunk_edit(root)
      before = [{ law: "TEST_RULE", severity: :warning, line: 2, message: "fix me" }]
      after = [{ law: "NEW_RULE", severity: :warning, line: 15, message: "untouched" }]
      loop = build_loop(root:, bus: FakeBus.new, scanner: SequenceScanner.new(before, after), agent: FixingAgent.new)

      assert loop.send(:apply, path, proposed, violation_in(path))
    end
  end

  # Thirty lines on disk, and a proposal that changes lines 2 and 28 only.
  def two_hunk_edit(root)
    path = File.join(root, "sample.rb")
    lines = (1..30).map { |n| "line_#{n} = #{n}\n" }
    File.write(path, lines.join)

    proposed = lines.dup
    proposed[1] = "line_2 = :two\n"
    proposed[27] = "line_28 = :two\n"
    [path, proposed.join]
  end

  # A violation the file already carried elsewhere is not the scout's business:
  # the golden rule forbids touching lines the fix did not need.
  def test_apply_keeps_a_preexisting_violation_on_an_untouched_line
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "violation\n")
      carried = [{ law: "OLD_RULE", severity: :warning, line: 9, message: "preexisting" }]
      loop = build_loop(root:, bus: FakeBus.new, scanner: SequenceScanner.new(carried, carried),
                        agent: FixingAgent.new)

      assert loop.send(:apply, path, "clean\n", violation_in(path))
    end
  end

  # The per-fix commit: an applied fix is committed under its rule's name,
  # scoped to its file, before the next violation is touched.
  def test_an_applied_fix_is_committed_immediately
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "violation\n")
      committer = FakeCommitter.new
      loop = build_loop(root:, bus: FakeBus.new, scanner: RecordingScanner.new,
                        agent: FixingAgent.new, committer:)

      outcome = loop.send(:fix_violation, violation_in(path))

      assert_equal :applied, outcome
      assert_equal "clean\n", File.read(path)
      assert_equal [path], committer.attested
      message, findings, owned_paths = committer.calls.first
      assert_equal "fix: TEST_RULE in sample.rb", message
      assert_equal [path], owned_paths
      assert_equal ["TEST_RULE"], findings.map { |f| f[:law] }
    end
  end

  # A commit that the hook or the remote refused does not undo the fix or kill
  # the pass: the fix is on disk, undelivered, and that is a different outcome
  # from :applied — one the stage-end commit can still pick up.
  def test_a_refused_commit_is_a_named_outcome_and_the_fix_stands
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "violation\n")
      bus = FakeBus.new
      committer = FakeCommitter.new(fail: true)
      loop = build_loop(root:, bus:, scanner: RecordingScanner.new,
                        agent: FixingAgent.new, committer:)

      outcome = loop.send(:fix_violation, violation_in(path))

      assert_equal :commit_refused, outcome
      assert_equal "clean\n", File.read(path)
      assert_includes bus.events.map(&:first), "repair_loop:commit_refused"
    end
  end

  # The committer records its own refusal with its reason; a :blocked that recorded none is the
  # committer's defect, and the repair says so instead of "blocked".
  def test_a_blocked_commit_without_a_recorded_reason_is_named_as_the_committers_defect
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "violation\n")
      committer = FakeCommitter.new
      committer.define_singleton_method(:commit_if_dirty) { |*, **| :blocked }

      committer.define_singleton_method(:last_refusal) { nil }
      loop = build_loop(root:, bus: FakeBus.new, scanner: RecordingScanner.new, agent: FixingAgent.new, committer:)

      said = []

      Master::Trace::Dmesg.stub(:status, ->(unit, text) { said << "#{unit}: #{text}" }) do
        assert_equal :commit_refused, loop.send(:fix_violation, violation_in(path))
      end
      assert_includes said, "fix0: sample.rb refused by commit: the committer answered :blocked and recorded no reason"
    end
  end

  def test_a_commit_that_raises_is_recorded_with_the_exception
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "violation\n")
      loop = build_loop(root:, bus: FakeBus.new, scanner: RecordingScanner.new, agent: FixingAgent.new,
                        committer: FakeCommitter.new(fail: true))
      said = []

      Master::Trace::Dmesg.stub(:status, ->(unit, text) { said << "#{unit}: #{text}" }) { loop.run_once([path]) }

      assert_includes said, "fix0: sample.rb refused by commit: RuntimeError: pre-commit hook refused"
    end
  end

  # :commit_refused still counts as work the stage must account for — counting
  # only :applied would strand the refused fixes with llm_fixed == 0 and no
  # stage-end commit ever chasing them.
  def test_a_refused_commit_still_counts_toward_the_stage_commit
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "violation\n")
      committer = FakeCommitter.new(fail: true)
      loop = build_loop(root:, bus: FakeBus.new, scanner: RecordingScanner.new,
                        agent: FixingAgent.new, committer:)

      result = loop.run_once([path])

      assert_equal 1, result[:fixed]
      assert_equal 1, result[:breakdown][:commit_refused]
    end
  end

  # MASTER_FIX_COMMIT_STAGE=1 keeps the old shape: one commit per stage.
  def test_stage_commit_mode_skips_the_per_fix_commit
    previous = ENV["MASTER_FIX_COMMIT_STAGE"]
    ENV["MASTER_FIX_COMMIT_STAGE"] = "1"
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "violation\n")
      committer = FakeCommitter.new
      loop = build_loop(root:, bus: FakeBus.new, scanner: RecordingScanner.new,
                        agent: FixingAgent.new, committer:)

      assert_equal :applied, loop.send(:fix_violation, violation_in(path))
      assert_empty committer.calls
    end
  ensure
    previous.nil? ? ENV.delete("MASTER_FIX_COMMIT_STAGE") : ENV["MASTER_FIX_COMMIT_STAGE"] = previous
  end

  # Without a committer the loop is unchanged: lean boots and the tests that
  # never wired one still fix and report :applied.
  def test_no_committer_means_no_commit_and_no_refusal
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "violation\n")
      loop = build_loop(root:, bus: FakeBus.new, scanner: RecordingScanner.new, agent: FixingAgent.new)

      assert_equal :applied, loop.send(:fix_violation, violation_in(path))
    end
  end

  def test_immediate_delivery_stops_the_batch_after_one_delivered_fix
    Dir.mktmpdir do |root|
      calls = []
      loop = build_loop(root:, bus: FakeBus.new, scanner: RecordingScanner.new,
                        agent: FixingAgent.new, committer: FakeCommitter.new)
      loop.define_singleton_method(:fix_violation) do |violation|
        calls << violation[:file]
        :applied
      end

      violations = [
        { file: File.join(root, "one.rb"), line: 1, rule: "TEST_RULE" },
        { file: File.join(root, "two.rb"), line: 1, rule: "TEST_RULE" },
      ]

      result = loop.send(:fix_batch, violations)

      assert_equal 1, result
      assert_equal [violations.first[:file]], calls
    end
  end
end
