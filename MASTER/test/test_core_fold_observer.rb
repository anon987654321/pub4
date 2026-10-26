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
    def propose(_context, verbs:, **) = @effects.shift || Master::Core::Effect.done("done")
  end

  def build(model, root:, observer: nil, effect_observer: nil, world: nil)
    Master::Core::Fold.new(
      model:,
      constitution: Master::Core::Constitution.new(laws: []),
      world: world || Master::Core::World.new(root:),
      memory: Master::Core::Memory.new,
      observer:,
      effect_observer:,
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
      block_writes = Master::Core::Constitution::Law.new(
        id: :no_writes, verbs: %i[write],
        judge: ->(_e, _m) { Master::Core::Verdict::Block.new(reason: "no", by: :no_writes) }
      )
      fold = Master::Core::Fold.new(
        model: ScriptedModel.new(Master::Core::Effect.write("a", "b"), Master::Core::Effect.done),
        constitution: Master::Core::Constitution.new(laws: [block_writes]),
        world: Master::Core::World.new(root:),
        memory: Master::Core::Memory.new,
        observer: ->(turn:, effect:, observation:) { seen << [effect.verb, observation.ok?] },
      )
      fold.run("goal")
      assert_includes seen, [:write, false]
    end
  end

  # A world whose effects fail and whose rollback answers as told.
  class FailingWorld
    def initialize(rollback)
      @rollback = rollback
      @rollback_calls = 0
    end

    def verbs = Master::Core::VERBS
    attr_reader :checkpoints, :rollback_calls

    def checkpoint
      @checkpoints = @checkpoints.to_i + 1
      { id: "cp1", patch: "" }
    end

    def perform(_effect) = Master::Core::Observation.no("boom")

    def rollback(_checkpoint, _effect)
      @rollback_calls += 1
      @rollback
    end
  end

  def failed_observation(effect, rollback)
    seen = []
    Master::Core::Fold.new(
      model: ScriptedModel.new(effect, Master::Core::Effect.done),
      constitution: Master::Core::Constitution.new(laws: []),
      world: FailingWorld.new(rollback),
      memory: Master::Core::Memory.new,
      observer: ->(turn:, effect:, observation:) { seen << observation },
    ).run("goal")
    seen.first
  end

  # World#rollback reports an effect it could not undo, and the fold used to
  # drop that report, so the agent believed a failed effect left no trace.
  def test_a_rollback_that_could_not_undo_rides_on_the_failure
    skipped = Master::Core::Observation.no("rollback skipped cp1: no path to scope to")
    observation = failed_observation(Master::Core::Effect.write("a.txt", "x"), skipped)

    refute_predicate observation, :ok?
    assert_match(/boom \[rollback skipped cp1/, observation.message)
  end

  # exec and git have no path to roll back to, so they cost no checkpoint.
  def test_only_a_write_takes_a_checkpoint
    taken = lambda do |effect|
      world = FailingWorld.new(Master::Core::Observation.ok("clean"))
      Master::Core::Fold.new(
        model: ScriptedModel.new(effect, Master::Core::Effect.done),
        constitution: Master::Core::Constitution.new(laws: []),
        world:, memory: Master::Core::Memory.new
      ).run("goal")
      world.checkpoints.to_i
    end

    assert_equal 1, taken.call(Master::Core::Effect.write("a.txt", "x"))
    assert_equal 0, taken.call(Master::Core::Effect.exec(["false"]))
    assert_equal 0, taken.call(Master::Core::Effect.git(:diff))
  end

  def test_an_undone_write_says_so_and_a_clean_exec_adds_nothing
    undone = Master::Core::Observation.ok("rolled back a.txt cp1")

    assert_match(/rolled back a\.txt/, failed_observation(Master::Core::Effect.write("a.txt", "x"), undone).message)
    assert_equal "boom", failed_observation(Master::Core::Effect.exec(["false"]), undone).message
  end

  def test_effect_lifecycle_surrounds_world_execution
    Dir.mktmpdir do |root|
      path = File.join(root, "effect.txt")
      seen = []
      effect_observer = lambda do |stage:, turn:, effect:, effect_id:, observation: nil, elapsed_ms: nil, **|
        next unless effect.verb == :write

        seen << { stage:, turn:, effect_id:, exists: File.exist?(path), ok: observation&.ok?, elapsed_ms: }
      end
      model = ScriptedModel.new(Master::Core::Effect.write("effect.txt", "payload"),
                                Master::Core::Effect.done("finished"))

      done = build(model, root:, effect_observer:).run("write and finish")

      assert_equal :complete, done.reason
      assert_equal %i[before after], seen.map { |event| event.fetch(:stage) }
      refute seen.first.fetch(:exists), "the before event must precede the file write"
      assert seen.last.fetch(:exists), "the after event must follow the file write"
      assert_equal seen.first.fetch(:effect_id), seen.last.fetch(:effect_id)
      assert_equal true, seen.last.fetch(:ok)
      assert_operator seen.last.fetch(:elapsed_ms), :>=, 0
    end
  end

  def test_lifecycle_publication_failure_prevents_effect_execution
    Dir.mktmpdir do |root|
      path = File.join(root, "must-not-exist.txt")
      effect_observer = lambda do |stage:, **|
        raise "ledger unavailable" if stage == :before
      end
      world = Object.new
      world.define_singleton_method(:verbs) { Master::Core::VERBS }
      world.define_singleton_method(:checkpoint) { { id: "cp", patch: "" } }
      world.define_singleton_method(:perform) { |_effect| flunk("World effect ran without a before event") }
      world.define_singleton_method(:rollback) { |*| flunk("an effect that never ran must not be rolled back") }
      model = ScriptedModel.new(Master::Core::Effect.write("must-not-exist.txt", "payload"),
                                Master::Core::Effect.done("finished"))

      done = build(model, root:, effect_observer:, world:).run("write safely")

      assert_equal :trace_failed, done.reason
      refute File.exist?(path)
      assert_match(/before event publication failed/, done.summary)
    end
  end

  def test_after_event_failure_does_not_claim_completion_or_repeat_the_effect
    Dir.mktmpdir do |root|
      path = File.join(root, "effect.txt")
      effect_observer = lambda do |stage:, effect:, **|
        raise "ledger unavailable" if stage == :after && effect.verb == :write
      end
      model = ScriptedModel.new(Master::Core::Effect.write("effect.txt", "payload"),
                                Master::Core::Effect.done("finished"))

      done = build(model, root:, effect_observer:).run("write safely")

      assert_equal :trace_failed, done.reason
      assert_equal "payload", File.read(path), "the completed side effect must not be misreported as failed and retried"
      assert_match(/after event publication failed/, done.summary)
    end
  end

  def test_rollback_is_its_own_lifecycle_pair_linked_to_the_failed_effect
    Dir.mktmpdir do |root|
      seen = []
      observer = lambda do |stage:, effect:, effect_id:, operation:, parent_effect_id: nil, checkpoint_id: nil, **|
        seen << { stage:, verb: effect.verb, effect_id:, operation:, parent_effect_id:, checkpoint_id: }
      end
      world = FailingWorld.new(Master::Core::Observation.ok("rolled back a.txt cp1"))
      model = ScriptedModel.new(Master::Core::Effect.write("a.txt", "x"), Master::Core::Effect.done("ok"))

      done = build(model, root:, effect_observer: observer, world:).run("write safely")

      assert_equal :complete, done.reason
      assert_equal [[:before, :perform], [:after, :perform], [:before, :rollback], [:after, :rollback]],
                   seen.map { |event| [event[:stage], event[:operation]] }
      perform_id = seen[0][:effect_id]
      rollback_id = seen[2][:effect_id]
      assert_equal perform_id, seen[2][:parent_effect_id]
      assert_equal "cp1", seen[2][:checkpoint_id]
      refute_equal perform_id, rollback_id
      assert_equal 1, world.rollback_calls
    end
  end

  def test_rollback_before_event_failure_does_not_run_the_rollback
    Dir.mktmpdir do |root|
      world = FailingWorld.new(Master::Core::Observation.ok("rolled back"))
      observer = lambda do |stage:, operation:, **|
        raise "ledger unavailable" if stage == :before && operation == :rollback
      end
      model = ScriptedModel.new(Master::Core::Effect.write("a.txt", "x"), Master::Core::Effect.done("ok"))

      done = build(model, root:, effect_observer: observer, world:).run("write safely")

      assert_equal :trace_failed, done.reason
      assert_equal 0, world.rollback_calls
    end
  end

  def test_failed_effect_with_missing_after_record_does_not_attempt_rollback
    Dir.mktmpdir do |root|
      world = FailingWorld.new(Master::Core::Observation.ok("rolled back"))
      observer = lambda do |stage:, operation:, **|
        raise "ledger unavailable" if stage == :after && operation == :perform
      end
      model = ScriptedModel.new(Master::Core::Effect.write("a.txt", "x"), Master::Core::Effect.done("ok"))

      done = build(model, root:, effect_observer: observer, world:).run("write safely")

      assert_equal :trace_failed, done.reason
      assert_equal 0, world.rollback_calls
    end
  end

  def test_no_observer_still_runs
    Dir.mktmpdir do |root|
      done = build(ScriptedModel.new(Master::Core::Effect.done("ok")), root:).run("g")
      assert_equal :complete, done.reason
    end
  end
end
