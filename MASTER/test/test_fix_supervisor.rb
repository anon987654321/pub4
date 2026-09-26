# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

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
      assert_equal Process.pid.to_s, saved["lease_owner"]
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
      assert_equal "completed", Master::Fix::Mission.current(root)["state"]
    end
  end
end