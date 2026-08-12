# frozen_string_literal: true

require "minitest/autorun"
require "master"
require "tmpdir"

# The observer lets a host watch the fold turn by turn without being able to
# change it. These pin that it fires once per turn with the recorded outcome,
# and that a fold with no observer behaves exactly as before (default nil).
class FoldObserverTest < Minitest::Test
  # Minimal offline model: emit a scripted list of effects, then done.
  class ScriptedModel
    def initialize(*effects) = @effects = effects
    def propose(_context, verbs:) = @effects.shift || Master::Core::Effect.done("done")
  end

  def build(model, root:, observer: nil)
    Master::Core::Fold.new(
      model:,
      constitution: Master::Core::Constitution.new(rules: []),
      world: Master::Core::World.new(root:),
      memory: Master::Core::Memory.new,
      observer:,
    )
  end

  def test_observer_fires_once_per_turn_with_outcome
    Dir.mktmpdir do |root|
      seen = []
      model = ScriptedModel.new(
        Master::Core::Effect.write("a.txt", "hi\n"),
        Master::Core::Effect.done("built"),
      )
      observer = ->(turn:, effect:, observation:) { seen << [turn, effect.verb, observation.ok?] }
      done = build(model, root:, observer:).run("goal")

      assert_equal :complete, done.reason
      assert_equal [[0, :write, true], [1, :done, true]], seen
    end
  end

  def test_observer_sees_blocked_effects_too
    Dir.mktmpdir do |root|
      seen = []
      # A rule that blocks every write; the fold observes the refusal and moves on.
      block_writes = Master::Core::Constitution::Rule.new(
        id: :no_writes, verbs: %i[write],
        judge: ->(_e, _m) { Master::Core::Verdict::Block.new(reason: "no", by: :no_writes) }
      )
      fold = Master::Core::Fold.new(
        model: ScriptedModel.new(Master::Core::Effect.write("a", "b"), Master::Core::Effect.done),
        constitution: Master::Core::Constitution.new(rules: [block_writes]),
        world: Master::Core::World.new(root:),
        memory: Master::Core::Memory.new,
        observer: ->(turn:, effect:, observation:) { seen << [effect.verb, observation.ok?] },
      )
      fold.run("goal")
      assert_includes seen, [:write, false]
    end
  end

  def test_no_observer_still_runs
    Dir.mktmpdir do |root|
      done = build(ScriptedModel.new(Master::Core::Effect.done("ok")), root:).run("g")
      assert_equal :complete, done.reason
    end
  end
end
