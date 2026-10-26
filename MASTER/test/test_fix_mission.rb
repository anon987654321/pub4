# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/trace/event_bus"
require_relative "../lib/trace/log"
require "tmpdir"
require "fileutils"
require "json"
require "digest"

class FixMissionTest < Minitest::Test
  class Bus
    attr_reader :events

    def initialize
      @events = []
    end

    def publish(event, payload = {})
      @events << [event, payload]
    end
  end

  def test_manual_fix_can_supersede_an_unclaimed_waiting_mission
    Dir.mktmpdir do |root|
      mission = Master::Fix::Mission.new(root:).ensure_queued!(
        goal: "play it on my sound card",
        scope: File.join(root, "MASTER"),
      )

      replacement = Master::Fix::Mission.new(root:).start_or_resume!(
        goal: "fix #{root}",
        scope: root,
        origin: "manual",
      )

      refute_equal mission.id, replacement.id
      assert_equal "running", replacement.record["state"]
      assert_equal "fix #{root}", replacement.record["goal"]
    end
  end

  def test_dead_same_host_mission_owner_does_not_block_another_target
    Dir.mktmpdir do |root|
      first = File.join(root, "RAILS")
      second = File.join(root, "MASTER")
      FileUtils.mkdir_p([first, second])

      mission = Master::Fix::Mission.new(root:).start!(goal: "fix RAILS", scope: first)
      record = Master::Fix::Mission.current(root:)
      record["lease_owner"] = "#{Socket.gethostname}:99999999:deadbeefdeadbeef"
      File.write(File.join(root, ".master", "mission.json"), JSON.pretty_generate(record) + "\n")

      replacement = Master::Fix::Mission.new(root:).start_or_resume!(goal: "fix MASTER", scope: second)
      saved = Master::Fix::Mission.current(root:)

      refute_equal mission.id, replacement.id
      assert_equal "MASTER", saved["scope"]
      assert_equal "running", saved["state"]
    end
  end

  def test_same_process_can_advance_to_another_target
    Dir.mktmpdir do |root|
      first = File.join(root, "RAILS")
      second = File.join(root, "MASTER")
      FileUtils.mkdir_p([first, second])

      mission = Master::Fix::Mission.new(root:).start!(goal: "fix RAILS", scope: first)
      replacement = Master::Fix::Mission.new(root:).start_or_resume!(
        goal: "fix MASTER", scope: second,
      )

      saved = Master::Fix::Mission.current(root:)
      refute_equal mission.id, replacement.id
      assert_equal "MASTER", saved["scope"]
      assert_equal "running", saved["state"]
    end
  end

  def test_mission_lifecycle_persists_one_contract
    Dir.mktmpdir do |root|
      bus = Bus.new
      mission = Master::Fix::Mission.new(root:, bus:).start!(
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

      record = Master::Fix::Mission.current(root:)
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

  def test_mission_lifecycle_evidence_redacts_goal_scope_and_summary
    Dir.mktmpdir do |root|
      goal = "repair private customer 7391"
      scope = "private/customer-7391"
      summary = "customer-specific repair details"
      bus = Master::Trace::EventBus.new(
        event_log: Master::Trace::Log::Event.new(root:),
        evidence_log: Master::Trace::Log::Evidence.new(root:)
      )
      mission = Master::Fix::Mission.new(root:, bus:).start!(
        goal:, scope:, model: "grok-cli:auto", effort: "medium"
      )
      mission.finish!(summary:)

      evidence_path = File.join(root, "runtime/events/evidence.jsonl")
      evidence = File.read(evidence_path)
      refute_includes evidence, goal
      refute_includes evidence, scope
      refute_includes evidence, summary
      assert_includes evidence, Digest::SHA256.hexdigest(goal)
      assert_includes evidence, Digest::SHA256.hexdigest(scope)
      assert_includes evidence, Digest::SHA256.hexdigest(summary)

      rows = File.readlines(evidence_path, chomp: true).map { |line| JSON.parse(line) }
      lifecycle = rows.select { |row| %w[mission:start mission:finish].include?(row["event"]) }
      assert_equal %w[mission:start mission:finish], lifecycle.map { |row| row["event"] }
      started = lifecycle.first.fetch("payload")
      finished = lifecycle.last.fetch("payload")
      assert_equal Digest::SHA256.hexdigest(goal), started["goal_digest"]
      assert_equal Digest::SHA256.hexdigest(scope), started["scope_digest"]
      assert_equal Digest::SHA256.hexdigest(summary), finished["summary_digest"]
      assert_equal "completed", finished["state"]
    end
  end

  def test_cancelled_and_ambiguous_missions_are_terminal_without_delivery_claims
    %w[cancelled unknown_outcome recovery_failed].each do |state|
      Dir.mktmpdir do |root|
        mission = Master::Fix::Mission.new(root:).start!(
          goal: "repair safely", scope: root, origin: "fold", auto_continue: true
        )
        mission.transition!(:execute)
        mission.finish!(state:, summary: "operator stopped")

        record = Master::Fix::Mission.current(root:)
        assert_equal state, record["state"]
        assert_equal "execute", record["stage"]
        refute_includes Master::Fix::Mission::RESUMABLE_STATES, record["state"]
      end
    end
  end

  def test_v1_mission_migrates_and_resumes_without_losing_identity
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, ".master"))
      legacy = {
        "version" => 1,
        "id" => "legacy-mission",
        "state" => "running",
        "stage" => "execute",
        "goal" => "resume the task",
        "scope" => root,
        "model" => "agy:auto",
        "effort" => "high",
        "plan" => "inspect then repair",
        "started_at" => "2026-09-30T20:00:00Z",
        "finished_at" => nil,
        "checkpoint" => nil,
        "artifacts" => ["README.md"],
        "error" => nil,
      }
      path = File.join(root, ".master", "mission.json")
      File.write(path, JSON.pretty_generate(legacy) + "\n")

      migrated = Master::Fix::Mission.current(root:)
      assert_equal 2, migrated["version"]
      assert_equal "waiting", migrated["state"]
      assert_equal "legacy-mission", migrated["id"]
      assert_equal false, migrated["auto_continue"]
      assert_nil migrated["lease_owner"]

      mission = Master::Fix::Mission.new(root:).start_or_resume!(
        goal: "resume the task",
        scope: root,
        model: "agy:auto",
        effort: "high",
        plan: "inspect then repair",
      )
      assert_equal "legacy-mission", mission.id
      assert_equal "running", mission.record["state"]
      assert_equal 2, mission.record["attempt_count"]

      persisted = JSON.parse(File.read(path))
      assert_equal 2, persisted["version"]
      assert_equal "legacy-mission", persisted["id"]
    end
  end

  def test_invalid_stage_and_effort_are_handled_deterministically
    Dir.mktmpdir do |root|
      mission = Master::Fix::Mission.new(root:).start!(goal: "x", effort: "absurd")
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
      mission = Master::Fix::Mission.new(root:, checkpoint:).start!(goal: "checkpoint", scope: root)
      mission.checkpoint!(files: ["file.txt"])

      checkpoint = mission.record["checkpoint"]
      assert checkpoint["id"]
      assert_equal ["file.txt"], checkpoint["files"]
      assert File.file?(File.join(root, ".master", "checkpoints", checkpoint["id"], "file.txt"))
    end
  end
  def test_v2_without_operator_is_normalized
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, ".master"))
      record = {
        "version" => 2, "id" => "old-v2", "state" => "waiting",
        "stage" => "verify", "goal" => "old", "scope" => root,
        "model" => "agy:auto", "effort" => "medium", "plan" => "inspect",
        "origin" => "fold", "auto_continue" => true
      }
      path = File.join(root, ".master", "mission.json")
      File.write(path, JSON.pretty_generate(record) + "\n")

      migrated = Master::Fix::Mission.current(root:)
      assert_equal "repair", migrated.dig("operator", "mode")
      Master::Fix::Mission.new(root:).wake!(reason: "check")
      assert File.read(path).include?("\"operator\"")
    end
  end

end
