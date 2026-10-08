# frozen_string_literal: true

require "test_helper"
require "cli/core_bridge"
require "tmpdir"

class CoreBridgePersistenceTest < Minitest::Test
  class ScriptedModel
    def initialize(*effects) = @effects = effects
    def propose(_context, verbs:, **) = @effects.shift || Master::Core::Effect.done("done")
  end

  def test_incomplete_fold_remains_the_same_mission_for_the_next_attempt
    Dir.mktmpdir do |root|
      first = ScriptedModel.new(Master::Core::Effect.exec(%w[echo continue]))
      result = Master::CLI::CoreBridge.run("finish the task", root:, model: first, max_turns: 1)

      assert_equal :max_turns, result[:reason]
      saved = Master::Fix::Mission.current(root:)
      assert_equal "fold", saved["origin"]
      assert_equal true, saved["auto_continue"]
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
