# frozen_string_literal: true

require "test_helper"
require "fix/task_steward"
require "tmpdir"

class TaskStewardTest < Minitest::Test
  def write_mission(root, next_wake_at: Time.now.utc.iso8601, auto_continue: true, origin: "fold")
    mission = Master::Fix::Mission.new(root:)
    mission.start!(goal: "finish the task", scope: root, origin:, auto_continue:)
    mission.send(:with_lock) do
      record = mission.instance_variable_get(:@record)
      record["state"] = "waiting"
      record["next_wake_at"] = next_wake_at
      record["lease_owner"] = nil
      record["lease_until"] = nil
      mission.send(:persist!)
    end
    mission
  end

  def test_tick_reenters_due_fold_mission
    Dir.mktmpdir do |root|
      mission = write_mission(root)
      calls = []
      steward = Master::Fix::TaskSteward.new(
        root:,
        bus: nil,
        runner: ->(goal:, mission:) { calls << [goal, mission["id"]]; :continued },
      )

      assert_equal :continued, steward.tick!
      assert_equal [[mission.record["goal"], mission.id]], calls
    end
  end

  def test_non_fold_missions_are_invisible
    Dir.mktmpdir do |root|
      write_mission(root, origin: "fix")
      calls = []
      steward = Master::Fix::TaskSteward.new(root:, bus: nil, runner: ->(**) { calls << true })
      assert_equal :idle, steward.tick!
      assert_empty calls
    end
  end

  def test_disabled_auto_continue_is_not_reentered
    Dir.mktmpdir do |root|
      write_mission(root, auto_continue: false)
      steward = Master::Fix::TaskSteward.new(root:, bus: nil, runner: ->(**) { flunk "should not run" })
      assert_equal :idle, steward.tick!
    end
  end

  def test_waiting_for_future_wake_is_not_reentered
    Dir.mktmpdir do |root|
      write_mission(root, next_wake_at: (Time.now.utc + 300).iso8601)
      steward = Master::Fix::TaskSteward.new(root:, bus: nil, runner: ->(**) { flunk "should not run" })
      assert_equal :idle, steward.tick!
    end
  end

  def test_active_lease_failure_does_not_defer_another_process
    Dir.mktmpdir do |root|
      write_mission(root)
      steward = Master::Fix::TaskSteward.new(
        root:,
        bus: nil,
        runner: ->(**) {
          mission = Master::Fix::Mission.new(root:)
          current = Master::Fix::Mission.current(root:)
          mission.start_or_resume!(goal: current["goal"], scope: root)
          mission.send(:with_lock) do
            record = mission.instance_variable_get(:@record)
            record["lease_owner"] = "other-host:42"
            record["lease_until"] = (Time.now.utc + 300).iso8601
            mission.send(:persist!)
          end
          raise "runner collision"
        },
      )

      result = steward.tick!
      assert result.err?
      saved = Master::Fix::Mission.current(root:)
      assert_equal "running", saved["state"]
      assert_equal "other-host:42", saved["lease_owner"]
    end
  end
end
