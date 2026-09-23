# frozen_string_literal: true

require_relative "test_helper"

class TestReliabilityKernel < Minitest::Test
  def test_deadline_uses_elapsed_time_not_wall_clock
    deadline = Master::Ground::Reliability::Deadline.new(1)

    assert_operator deadline.remaining, :<=, 1.0
    refute deadline.expired?
    assert_operator deadline.at, :>, Time.now
  end

  def test_deadline_rejects_non_positive_budget
    assert_raises(ArgumentError) { Master::Ground::Reliability::Deadline.new(0) }
    assert_raises(ArgumentError) { Master::Ground::Reliability::Deadline.new(-1) }
  end

  def test_status_has_explicit_health_states
    assert Master::Ground::Reliability::Status.healthy.healthy?
    assert Master::Ground::Reliability::Status.degraded("offline").degraded?
    assert Master::Ground::Reliability::Status.failed("disk").failed?
  end

  def test_fix_journal_records_and_resumes_an_interrupted_run
    Dir.mktmpdir("master-reliability") do |root|
      journal = Master::Fix::RunJournal.new(root:)
      first = journal.start_or_resume(target: root, files: [File.join(root, "a.rb")],
                                      max_passes: 15, budget_seconds: 60)
      journal.pass_start(first["id"], 1, transaction_id: "test-pass")
      journal.pass_finish(first["id"], 1, status: :continue, message: "still fixing")

      resumed = Master::Fix::RunJournal.new(root:).start_or_resume(
        target: root, files: [File.join(root, "a.rb")], max_passes: 15, budget_seconds: 60,
      )

      assert_equal first["id"], resumed["id"]
      assert resumed["resumed"]
      assert_equal 2, Master::Fix::RunJournal.new(root:).next_pass(resumed)
      assert_equal 1, resumed["resume_count"]
    end
  end

  def test_fix_journal_replays_an_active_pass_after_crash
    Dir.mktmpdir("master-reliability") do |root|
      journal = Master::Fix::RunJournal.new(root:)
      first = journal.start_or_resume(target: root, files: [], max_passes: 5, budget_seconds: 30)
      journal.pass_start(first["id"], 1, transaction_id: "test-pass")
      journal.crash(first["id"], "killed during pass")

      resumed = Master::Fix::RunJournal.new(root:).start_or_resume(
        target: root, files: [], max_passes: 5, budget_seconds: 30,
      )

      assert resumed["resumed"]
      assert_equal "active", resumed["state"]
      assert_equal 1, Master::Fix::RunJournal.new(root:).next_pass(resumed)
    end
  end

  def test_fix_journal_marks_terminal_runs_and_starts_the_next_run
    Dir.mktmpdir("master-reliability") do |root|
      journal = Master::Fix::RunJournal.new(root:)
      first = journal.start_or_resume(target: root, files: [], max_passes: 1, budget_seconds: 5)
      journal.terminal(first["id"], :done, message: "clean")
      second = journal.start_or_resume(target: root, files: [], max_passes: 1, budget_seconds: 5)

      refute_equal first["id"], second["id"]
      refute second["resumed"]
      assert_equal "active", second["state"]
    end
  end

  def test_corrupt_journal_fails_loudly
    Dir.mktmpdir("master-reliability") do |root|
      path = File.join(root, Master::Fix::RunJournal::PATH)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "{not-json")

      error = assert_raises(RuntimeError) do
        Master::Fix::RunJournal.new(root:).history
      end

      assert_match(/fix journal is corrupt/, error.message)
    end
  end
end
