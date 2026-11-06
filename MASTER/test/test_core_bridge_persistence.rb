# frozen_string_literal: true

require "test_helper"
require "cli/core_bridge"
require "tmpdir"
require "digest"

class CoreBridgePersistenceTest < Minitest::Test
  class ScriptedModel
    def initialize(*effects) = @effects = effects
    def propose(_context, verbs:, **) = @effects.shift || Master::Core::Effect.done("done")
  end

  def test_incomplete_authorised_repair_resumes_one_mission_and_keeps_its_delivery_grant
    Dir.mktmpdir do |root|
      File.write(File.join(root, "source.rb"), "SOURCE = 0\n")
      first_memory = Master::Core::Memory.new
      first_memory.proof.mark_ideation_complete!(approaches: Master::Core::Proof::ALTERNATIVES_REQUIRED)
      first = ScriptedModel.new(Master::Core::Effect.write("source.rb", "SOURCE = 1\n"))
      result = Master::CLI::CoreBridge.run("please fix all", root:, model: first, memory: first_memory, max_turns: 1)

      assert_equal :max_turns, result[:reason]
      saved = Master::Fix::Mission.current(root:)
      assert_equal true, saved["auto_continue"]
      assert_equal "run_full_workflow", saved.dig("operator", "intent")
      assert_equal "high", saved.dig("operator", "risk")

      assert_equal Digest::SHA256.hexdigest("SOURCE = 1\n"), saved.dig("repository_writes", "source.rb")

      resumed_memory = Master::Core::Memory.new(risk: :low)
      resumed = Master::CLI::CoreBridge.run(
        "go on", root:, model: ScriptedModel.new(Master::Core::Effect.read("source.rb")),
        memory: resumed_memory, max_turns: 1,
      )

      assert_equal :max_turns, resumed[:reason]
      assert_equal saved["id"], resumed[:mission]["id"]
      assert_equal 2, resumed[:mission]["attempt_count"]
      assert_equal "repair", resumed[:mission].dig("operator", "mode")
      assert_equal "high", resumed[:mission].dig("operator", "risk")
      assert_equal true, resumed_memory.proof.scope[:repository_delivery]
      assert_includes resumed_memory.proof.scope[:delivery_paths], "source.rb"
      assert_equal :high, resumed_memory.proof.risk
    end
  end

  def test_plain_conversation_does_not_start_an_unattended_mission
    Dir.mktmpdir do |root|
      result = Master::CLI::CoreBridge.run(
        "what is in this file?", root:,
        model: ScriptedModel.new(Master::Core::Effect.done("nothing changed")),
        max_turns: 1,
      )

      assert_equal false, result[:mission]["auto_continue"]
    end
  end

  def test_incomplete_fold_remains_the_same_mission_for_the_next_attempt
    Dir.mktmpdir do |root|
      first = ScriptedModel.new(Master::Core::Effect.exec(%w[echo continue]))
      result = Master::CLI::CoreBridge.run("finish the task", root:, model: first, max_turns: 1)

      assert_equal :max_turns, result[:reason]
      saved = Master::Fix::Mission.current(root:)
      assert_equal "fold", saved["origin"]
      assert_equal false, saved["auto_continue"], "ordinary conversation does not grant unattended repair"
      assert_equal "waiting", saved["state"]
      mission_id = saved["id"]

      second = ScriptedModel.new(
        Master::Core::Effect.exec(%w[echo rake test], evidence: :test_pass),
        Master::Core::Effect.exec(%w[echo rubocop], evidence: :scan_clean),
        Master::Core::Effect.exec(%w[echo rake review], evidence: :code_review),
        Master::Core::Effect.done("finished"),
      )
      resumed = Master::CLI::CoreBridge.run("finish the task", root:, model: second, max_turns: 4)

      assert_equal :complete, resumed[:reason]
      assert_equal mission_id, resumed[:mission]["id"]
      assert_equal 2, resumed[:mission]["attempt_count"]
      assert_equal "completed", resumed[:mission]["state"]
      assert_equal "finished", resumed[:mission]["summary"]
    end
  end
end
