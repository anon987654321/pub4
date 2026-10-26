# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class AssistantTasksTest < Minitest::Test
  Tasks = Master::Ground::AssistantTasks

  def setup
    @root = Dir.mktmpdir("master-assistant-tasks-")
    @now = Time.utc(2026, 10, 21, 20, 0, 0)
    Fiber[:master_visitor] = nil
    Fiber[:master_pair_subject] = nil
    @tasks = Tasks.new(root: @root, clock: -> { @now })
  end

  def teardown
    FileUtils.rm_rf(@root)
    Fiber[:master_visitor] = nil
    Fiber[:master_pair_subject] = nil
  end

  def call(action, **args)
    @tasks.call(action:, **args)
  end

  def test_tasks_persist_with_owner_only_permissions
    created = call("create", title: "Prepare launch", due_at: "2026-10-22T12:00:00Z", priority: "high")
    id = created.fetch("id")
    path = File.join(@root, ".master", "workspace", "local-uid-#{Process.uid}", "TASKS.json")

    assert File.file?(path)
    assert_equal 0o600, File.stat(path).mode & 0o777
    assert_equal 0o700, File.stat(File.dirname(path)).mode & 0o777
    assert_equal "Prepare launch", call("show", id:)["title"]
    assert_equal "high", call("show", id:)["priority"]
  end

  def test_task_completion_requires_step_evidence
    created = call("create", title: "Ship feature")
    id = created.fetch("id")
    step = call("add_step", id:, step_title: "Run tests").fetch("step")

    assert_raises(Tasks::Error) { call("complete", id:, evidence: "looks good") }
    call("start_step", id:, step_id: step.fetch("id"), note: "Running focused tests")
    verified = call("verify_step", id:, step_id: step.fetch("id"), evidence: "ruby -Itest test/test_feature.rb: 12 runs, 0 failures")
    assert_equal "verified", verified.fetch("step").fetch("state")

    completed = call("complete", id:, evidence: "Focused tests passed; result recorded above")
    assert_equal "completed", completed.fetch("state")
    assert_equal "completed", call("show", id:)["state"]
    assert_match(/not independently authenticated/, completed.fetch("verification_semantics"))
  end

  def test_blocked_task_requires_explicit_resume
    task = call("create", title: "Wait for access")
    blocked = call("block", id: task.fetch("id"), note: "Waiting for operator approval")
    assert_equal "blocked", blocked.fetch("state")
    assert_raises(Tasks::Error) { call("update", id: task.fetch("id"), title: "New title") }

    resumed = call("resume", id: task.fetch("id"), note: "Operator supplied access")
    assert_equal "open", resumed.fetch("state")
    assert_equal "New title", call("update", id: task.fetch("id"), title: "New title")["title"]
  end

  def test_due_date_can_be_cleared_and_bad_dates_are_rejected
    task = call("create", title: "Pay bill", due_at: "2026-10-22T12:00:00Z")
    assert_raises(Tasks::Error) { call("update", id: task.fetch("id"), due_at: "tomorrow") }
    updated = call("update", id: task.fetch("id"), due_at: "none")
    assert_nil updated["due_at"]
  end

  def test_past_due_tasks_are_marked_without_claiming_notifications
    call("create", title: "Overdue task", due_at: "2026-10-20T12:00:00Z")
    overdue = call("list").fetch("tasks").find { |row| row["title"] == "Overdue task" }

    assert_equal true, overdue.fetch("overdue")
    assert_match(/nothing rings while no session is open/, call("list").fetch("note"))
  end

  def test_list_is_bounded_searchable_and_marks_notification_limitation
    55.times { |i| call("create", title: "Routine task #{i}") }

    all = call("list")
    assert_equal 55, all.fetch("count")
    assert_equal 50, all.fetch("tasks").size
    assert_equal true, all.fetch("truncated")
    assert_match(/nothing rings while no session is open/, all.fetch("note"))
    assert_equal false, all.fetch("tasks").find { |row| row["title"] == "Routine task 54" }.fetch("overdue")
    assert_equal 1, call("list", query: "Routine task 54").fetch("tasks").size
  end

  def test_visitor_cannot_read_or_mutate_the_personal_task_ledger
    Fiber[:master_visitor] = true
    assert_raises(Tasks::Error) { call("list") }
    assert_raises(Tasks::Error) { call("create", title: "private") }
    refute File.exist?(File.join(@root, ".master", "workspace", "local-uid-#{Process.uid}", "TASKS.json"))
  end

  def test_symlinked_ledger_is_refused
    dir = File.join(@root, ".master", "workspace", "local-uid-#{Process.uid}")
    FileUtils.mkdir_p(dir)
    outside = File.join(@root, "outside.json")
    File.write(outside, '{"schema":1,"tasks":[],"events":[]}')
    File.symlink(outside, File.join(dir, "TASKS.json"))

    assert_raises(Tasks::Error) { call("list") }
  end

  def test_each_subject_has_a_separate_task_ledger
    alice = Tasks.new(root: @root, subject: "alice", clock: -> { @now })
    bob = Tasks.new(root: @root, subject: "bob", clock: -> { @now })

    alice.call(action: "create", title: "Alice private task")
    bob.call(action: "create", title: "Bob private task")

    assert_equal ["Alice private task"], alice.call(action: "list").fetch("tasks").map { |row| row["title"] }
    assert_equal ["Bob private task"], bob.call(action: "list").fetch("tasks").map { |row| row["title"] }
    assert File.file?(File.join(@root, ".master", "workspace", "alice", "TASKS.json"))
    assert File.file?(File.join(@root, ".master", "workspace", "bob", "TASKS.json"))
  end

  def test_corrupt_task_shapes_are_refused_without_overwriting
    path = File.join(@root, ".master", "workspace", "local-uid-#{Process.uid}", "TASKS.json")
    FileUtils.mkdir_p(File.dirname(path))
    corrupt = '{"schema":1,"tasks":[null],"events":[]}'
    File.write(path, corrupt)

    assert_raises(Tasks::Error) { call("create", title: "Must not replace corruption") }
    assert_equal corrupt, File.read(path)
  end

  def test_task_and_step_limits_fail_without_corrupting_existing_state
    task = call("create", title: "Bounded task")
    32.times { |i| call("add_step", id: task.fetch("id"), step_id: "step#{i}", step_title: "Step #{i}") }
    assert_raises(Tasks::Error) { call("add_step", id: task.fetch("id"), step_title: "Overflow") }
    assert_equal 32, call("show", id: task.fetch("id")).fetch("steps").size
  end
end
