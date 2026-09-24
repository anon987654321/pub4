# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "json"

class CoreMissionTest < Minitest::Test
  class Bus
    attr_reader :events

    def initialize
      @events = []
    end

    def publish(event, payload = {})
      @events << [event, payload]
    end
  end

  def test_mission_lifecycle_persists_one_contract
    Dir.mktmpdir do |root|
      bus = Bus.new
      mission = Master::Core::Mission.new(root:, bus:).start!(
        goal: "fix the face",
        scope: root,
        model: "agy:auto",
        effort: "high",
        plan: "explore then verify",
      )

      mission.transition!(:plan, plan: "inspect before changing")
      mission.transition!(:execute)
      mission.transition!(:verify)
      mission.finish!(summary: "clean")

      record = Master::Core::Mission.current(root:)
      assert_equal mission.id, record["id"]
      assert_equal "completed", record["state"]
      assert_equal "deliver", record["stage"]
      assert_equal "agy:auto", record["model"]
      assert_equal "high", record["effort"]
      assert_equal "inspect before changing", record["plan"]
      assert_equal "clean", record["summary"]
      assert_equal %w[mission:start mission:stage mission:stage mission:stage mission:finish],
                   bus.events.map(&:first)
    end
  end

  def test_invalid_stage_and_effort_are_handled_deterministically
    Dir.mktmpdir do |root|
      mission = Master::Core::Mission.new(root:).start!(goal: "x", effort: "absurd")
      assert_equal "medium", mission.record["effort"]
      assert_raises(ArgumentError) { mission.transition!(:teleport) }
    end
  end

  def test_checkpoint_uses_existing_checkpoint_store
    Dir.mktmpdir do |root|
      File.write(File.join(root, "file.txt"), "before")
      checkpoint = ->(id:, root:, files:) do
        Master::Fix::Checkpoint.new(root:, dir: File.join(root, ".master", "checkpoints")).create(
          label: "mission-#{id}", files:,
        )
      end
      mission = Master::Core::Mission.new(root:, checkpoint:).start!(goal: "checkpoint", scope: root)
      mission.checkpoint!(files: ["file.txt"])

      checkpoint = mission.record["checkpoint"]
      assert checkpoint["id"]
      assert_equal ["file.txt"], checkpoint["files"]
      assert File.file?(File.join(root, ".master", "checkpoints", checkpoint["id"], "file.txt"))
    end
  end
end
