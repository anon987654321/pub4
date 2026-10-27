# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "json"

class FixSupervisorTest < Minitest::Test
  def queue_mission(root)
    Master::Fix::Mission.new(root:).ensure_queued!(
      goal: "fix #{root}",
      scope: root,
      model: "test:model",
      effort: "high",
      plan: "observe, repair, verify",
    )
  end

  def test_queued_mission_survives_a_deferred_attempt_and_can_be_woken
    Dir.mktmpdir do |root|
      mission = queue_mission(root)
      assert_equal "waiting", mission.record["state"]
      assert mission.due?

      mission.defer!(reason: "plateau", seconds: 3600)
      saved = Master::Fix::Mission.current(root:)
      refute saved["next_wake_at"].nil?
      assert Time.iso8601(saved["next_wake_at"]) > Time.now.utc

      Master::Fix::Mission.new(root:).wake!(reason: "source_changed")
      saved = Master::Fix::Mission.current(root:)
      assert Time.iso8601(saved["next_wake_at"]) <= Time.now.utc
      assert_equal "source_changed", saved["wake_reason"]
    end
  end

  def test_event_during_running_attempt_is_latched_for_the_next_attempt
    Dir.mktmpdir do |root|
      mission = Master::Fix::Mission.new(root:).start!(goal: "fix #{root}", scope: root)
      mission.wake!(reason: "source_changed")

      saved = Master::Fix::Mission.current(root:)
      assert_equal "running", saved["state"]
      assert_equal true, saved["wake_requested"]

      fresh = Master::Fix::Mission.new(root:)
      assert fresh.requeue_if_requested!
      saved = Master::Fix::Mission.current(root:)
      assert_equal "waiting", saved["state"]
      assert saved["next_wake_at"]
      assert_equal false, saved["wake_requested"]
      assert saved["lease_owner"].nil?
    end
  end

  def test_expired_running_lease_is_reclaimable
    Dir.mktmpdir do |root|
      mission = Master::Fix::Mission.new(root:).start!(goal: "fix #{root}", scope: root)
      record = Master::Fix::Mission.current(root:)
      record["lease_until"] = (Time.now.utc - 1).iso8601
      File.write(File.join(root, ".master", "mission.json"), JSON.pretty_generate(record) + "\n")

      resumed = Master::Fix::Mission.new(root:).start_or_resume!(goal: "fix #{root}", scope: root)
      saved = Master::Fix::Mission.current(root:)
      assert_equal mission.id, resumed.id
      assert_operator saved["attempt_count"].to_i, :>=, 2
      assert_equal Master::Fix::Mission.instance_id, saved["lease_owner"]
    end
  end

  def test_expired_running_mission_does_not_block_another_target
    Dir.mktmpdir do |root|
      first = File.join(root, "RAILS")
      second = File.join(root, "MASTER")
      FileUtils.mkdir_p([first, second])

      Master::Fix::Mission.new(root:).start!(
        goal: "fix RAILS",
        scope: first,
      )
      record = Master::Fix::Mission.current(root:)
      record["lease_until"] = (Time.now.utc - 1).iso8601
      File.write(File.join(root, ".master", "mission.json"), JSON.pretty_generate(record) + "\n")

      replacement = Master::Fix::Mission.new(root:).start_or_resume!(
        goal: "fix MASTER",
        scope: second,
      )
      saved = Master::Fix::Mission.current(root:)

      refute_equal record["id"], replacement.id
      assert_equal "MASTER", saved["scope"]
      assert_equal "running", saved["state"]
      assert_equal replacement.id, saved["id"]
    end
  end

  def test_lease_owner_is_unique_to_the_current_master_instance
    owner = Master::Fix::Mission.instance_id
    assert_match(/:\d+:[0-9a-f]{16}\z/, owner)
    refute_equal Process.pid.to_s, owner
  end

  def test_foreign_running_lease_is_not_extended
    Dir.mktmpdir do |root|
      mission = Master::Fix::Mission.new(root:).start!(goal: "fix #{root}", scope: root)
      record = Master::Fix::Mission.current(root:)
      record["lease_owner"] = "other-host:1234:deadbeefdeadbeef"
      before = record["lease_until"]
      File.write(File.join(root, ".master", "mission.json"), JSON.pretty_generate(record) + "\n")

      Master::Fix::Mission.new(root:).heartbeat!
      saved = Master::Fix::Mission.current(root:)
      assert_equal before, saved["lease_until"]
    end
  end

  # A crashed run whose deadline passed while nothing ran it gives way to a new run.
  def test_a_spent_run_is_not_resumed
    Dir.mktmpdir do |root|
      journal, old_id = spent_run(root, mid_pass: false)
      fresh = start_master(journal, root)

      refute_equal old_id, fresh["id"]
      assert fresh["remaining_seconds"].positive?
      assert_equal "interrupted", journal.history.find { |row| row["id"] == old_id }["state"]
    end
  end

  # One stopped mid-pass still holds a transaction, so it is resumed for recovery, spent or not.
  def test_a_spent_run_stopped_mid_pass_is_resumed
    Dir.mktmpdir do |root|
      journal, old_id = spent_run(root, mid_pass: true)

      assert_equal old_id, start_master(journal, root)["id"]
    end
  end

  # A run stopped by hand with budget left is resumed by default.
  def test_a_stopped_run_with_budget_left_is_resumed
    Dir.mktmpdir do |root|
      journal, old_id = stopped_run(root)

      assert_equal old_id, start_master(journal, root)["id"]
    end
  end

  # bin/fix-here asks for a fresh run, and the stopped one is closed rather than resumed.
  def test_a_fresh_run_releases_a_stopped_run_with_budget_left
    Dir.mktmpdir do |root|
      journal, old_id = stopped_run(root)
      ENV["MASTER_FIX_FRESH"] = "1"

      refute_equal old_id, start_master(journal, root)["id"]
      assert_equal "interrupted", journal.history.find { |row| row["id"] == old_id }["state"]
    ensure
      ENV.delete("MASTER_FIX_FRESH")
    end
  end

  def stopped_run(root)
    journal = Master::Fix::RunJournal.new(root:)
    id = start_master(journal, root).fetch("id")
    journal.crash(id, "stopped")
    orphan!(root, id)
    [journal, id]
  end

  def orphan!(root, id)
    path = File.join(root, ".master", "fix_runs.json")
    data = JSON.parse(File.read(path))
    data["runs"].find { |row| row["id"] == id }["pid"] = 0
    File.write(path, JSON.generate(data))
  end

  def start_master(journal, root)
    target = File.join(root, "MASTER")
    FileUtils.mkdir_p(target)
    journal.start_or_resume(target:, files: [target], max_passes: 1, budget_seconds: 60)
  end

  # A MASTER run that crashed, with its deadline an hour gone and no process holding it.
  def spent_run(root, mid_pass:)
    journal = Master::Fix::RunJournal.new(root:)
    id = start_master(journal, root).fetch("id")
    journal.pass_start(id, 1, transaction_id: "tx-1") if mid_pass
    journal.crash(id, "stopped")

    path = File.join(root, ".master", "fix_runs.json")
    data = JSON.parse(File.read(path))
    data["runs"].find { |row| row["id"] == id }.merge!("deadline_at" => (Time.now.utc - 3600).iso8601, "pid" => 0)
    File.write(path, JSON.generate(data))
    [journal, id]
  end

  def test_same_process_can_advance_a_sequential_target_queue
    Dir.mktmpdir do |root|
      first = File.join(root, "MASTER")
      second = File.join(root, "RAILS")
      FileUtils.mkdir_p([first, second])

      journal = Master::Fix::RunJournal.new(root:)
      journal.start_or_resume(target: first, files: [first], max_passes: 1, budget_seconds: 60)

      replacement = journal.start_or_resume(target: second, files: [second], max_passes: 1, budget_seconds: 60)
      history = journal.history

      assert_equal "RAILS", replacement["target"]
      assert_equal "interrupted", history.find { |row| row["target"] == "MASTER" }["state"]
      assert_equal replacement["id"], history.last["id"]
    end
  end

  def test_supervisor_runs_only_when_the_persisted_mission_is_due
    Dir.mktmpdir do |root|
      queue_mission(root)
      calls = 0
      supervisor = nil
      loop_stub = Object.new
      loop_stub.define_singleton_method(:run) do |_target|
        calls += 1
        Master::Fix::Mission.new(root:).finish!(summary: "done")
        supervisor.stop!
      end

      supervisor = Master::Fix::Supervisor.new(root:, target: root, fix_loop: loop_stub)
      supervisor.run_forever

      assert_equal 1, calls
      assert_equal "completed", Master::Fix::Mission.current(root:)["state"]
    end
  end

  def test_active_mission_cannot_be_replaced_by_another_target
    Dir.mktmpdir do |root|
      first = File.join(root, "RAILS", "brgen")
      second = File.join(root, "RAILS", "amber")
      FileUtils.mkdir_p([first, second])

      mission = Master::Fix::Mission.new(root:).start!(
        goal: "fix RAILS/brgen",
        scope: first,
        model: "test:model",
        effort: "high",
        plan: "observe, repair, verify",
      )

      record = Master::Fix::Mission.current(root:)
      record["lease_owner"] = "other-host:1234:deadbeefdeadbeef"
      File.write(File.join(root, ".master", "mission.json"), JSON.pretty_generate(record) + "\n")

      error = assert_raises(RuntimeError) do
        Master::Fix::Mission.new(root:).start_or_resume!(
          goal: "fix RAILS/amber",
          scope: second,
          model: "test:model",
          effort: "high",
          plan: "observe, repair, verify",
        )
      end

      assert_match(/mission already active for RAILS\/brgen/, error.message)
      saved = Master::Fix::Mission.current(root:)
      assert_equal mission.id, saved["id"]
      assert_equal "RAILS/brgen", saved["scope"]
      assert_equal "running", saved["state"]
    end
  end

  def test_queueing_another_target_does_not_overwrite_running_mission
    Dir.mktmpdir do |root|
      first = File.join(root, "MASTER")
      second = File.join(root, "OPENBSD")
      FileUtils.mkdir_p([first, second])

      Master::Fix::Mission.new(root:).start!(
        goal: "fix MASTER",
        scope: first,
      )

      error = assert_raises(RuntimeError) do
        Master::Fix::Mission.new(root:).ensure_queued!(
          goal: "fix OPENBSD",
          scope: second,
        )
      end

      assert_match(/mission already active for MASTER/, error.message)
      assert_equal "MASTER", Master::Fix::Mission.current(root:)["scope"]
    end
  end
end
