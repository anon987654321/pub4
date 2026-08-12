# frozen_string_literal: true

require "minitest/autorun"
$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "result"
require "master"

class CritiqueFoldTest < Minitest::Test
  class ScriptedModel
    def initialize(*effects) = @effects = effects
    def propose(_context, verbs:) = @effects.shift || Master::Core::Effect.done("shipped")
  end

  def constitution
    Master::Core::Constitution.load(data_dir: File.expand_path("../../data", __dir__))
  end

  def test_critique_effect_records_council_pass
    memory = Master::Core::Memory.new(risk: :high)
    memory.mark_ideation_complete!
    runner = lambda do |**_|
      Master::Result.ok("critique: council pass")
    end
    world = Master::Core::World.new(root: Dir.mktmpdir, critique_runner: runner)
    observation = world.perform(Master::Core::Effect.critique)
    memory.record(Master::Core::Effect.critique, observation)

    assert memory.council_cleared?
  end

  def test_high_risk_fold_completes_with_critique
    Dir.mktmpdir do |root|
      memory = Master::Core::Memory.new(risk: :high)
      memory.note(:goal, "ship fix")
      memory.mark_ideation_complete!
      model = ScriptedModel.new(
        Master::Core::Effect.exec(["true"], evidence: :test_pass),
        Master::Core::Effect.exec(["true"], evidence: :scan_clean),
        Master::Core::Effect.exec(["true"], evidence: :code_review),
        Master::Core::Effect.critique,
        Master::Core::Effect.done("shipped"),
      )
      runner = lambda do |**_| Master::Result.ok("critique: council pass") end
      done = Master::Core::Fold.new(
        model:,
        constitution:,
        world: Master::Core::World.new(root:, critique_runner: runner),
        memory:,
      ).run("ship fix")

      assert_equal :complete, done.reason
    end
  end
end
