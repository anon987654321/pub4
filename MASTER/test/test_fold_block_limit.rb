# frozen_string_literal: true

require "test_helper"
require "core/fold"

class FoldBlockLimitTest < Minitest::Test
  class ScriptedModel
    def initialize(*effects) = @effects = effects

    def propose(_context, **)
      @effects.shift || raise("fold proposed more effects than expected")
    end
  end

  class ChangingLaw
    def initialize = @count = 0

    def admit(_effect, _memory)
      @count += 1
      Master::Core::Verdict::Block.new(reason: "reason #{@count}", by: "same_law")
    end
  end

  class Memory
    attr_reader :proof, :records

    def initialize
      @proof = Struct.new(:scope).new({})
      @records = []
    end

    def note(*) = self
    def context = []
    def record(effect, observation) = @records << [effect, observation]
  end

  class World
    def verbs = Master::Core::VERBS
  end

  class CapabilityLaw
    def admit(_effect, _memory)
      Master::Core::Verdict::Block.new(reason: "capability refused: execute", by: :capability)
    end
  end

  class RequiringApprovalLaw
    def admit(effect, _memory)
      Master::Core::Verdict::Request.new(
        effect:, prompt: "approve this operation?", reason: "operator approval required", by: :same_law,
      )
    end
  end

  class ChangingApprovalLaw
    def initialize = @count = 0

    def admit(effect, _memory)
      @count += 1
      Master::Core::Verdict::Request.new(
        effect:, prompt: "approve this operation?", reason: "operator approval required #{@count}", by: :same_law,
      )
    end
  end

  class DecliningWorld
    attr_reader :asked

    def initialize = @asked = []
    def verbs = Master::Core::VERBS

    def perform(effect)
      @asked << effect
      Master::Core::Observation.ok("no")
    end
  end

  def test_different_effects_blocked_by_the_same_law_stop_after_three
    effects = [
      Master::Core::Effect.read("one.rb"),
      Master::Core::Effect.read("two.rb"),
      Master::Core::Effect.read("three.rb"),
      Master::Core::Effect.done("must not finish"),
    ]
    memory = Memory.new
    emitted = []
    fold = Master::Core::Fold.new(
      model: ScriptedModel.new(*effects),
      constitution: ChangingLaw.new,
      world: World.new,
      memory:,
      max_turns: 10,
      observer: ->(**event) { emitted << event },
    )

    result = fold.run("exercise one constitutional check")

    assert_equal :blocked, result.reason
    assert_equal 3, result.turns
    assert_match(/stopped after 3 constitutional blocks by same_law/, result.summary)
    assert_equal 3, memory.records.length
    assert_equal 3, emitted.length
  end

  def test_repeated_declines_stop_after_the_approval_refusal_limit
    effect = Master::Core::Effect.exec(%w[ruby -v])
    memory = Memory.new
    world = DecliningWorld.new
    fold = Master::Core::Fold.new(
      model: ScriptedModel.new(*Array.new(5, effect)),
      constitution: ChangingApprovalLaw.new,
      world:,
      memory:,
      max_turns: 10,
    )

    result = fold.run("exercise repeated approval refusals")

    assert_equal :needs_user, result.reason
    assert_equal 3, result.turns
    assert_equal 3, world.asked.count { |asked| asked.verb == :ask }
    assert_equal 3, memory.records.length
    assert_match(/stopped after 3 constitutional blocks by same_law/, result.summary)
  end

  def test_a_repeated_refusal_of_the_same_effect_stops_before_the_global_limit
    effect = Master::Core::Effect.exec(%w[ruby -v])
    memory = Memory.new
    world = DecliningWorld.new
    fold = Master::Core::Fold.new(
      model: ScriptedModel.new(*Array.new(5, effect)),
      constitution: RequiringApprovalLaw.new,
      world:,
      memory:,
      max_turns: 10,
    )

    result = fold.run("exercise a repeated approval refusal")

    assert_equal :needs_user, result.reason
    assert_equal 2, result.turns
    assert_equal 2, world.asked.count { |asked| asked.verb == :ask }
    assert_match(/stopped after repeated exec refusal by same_law/, result.summary)
  end

  def test_capability_refusal_says_what_was_unavailable_and_that_nothing_ran
    effect = Master::Core::Effect.exec(["telegram-cli", "login"])
    memory = Memory.new
    fold = Master::Core::Fold.new(
      model: ScriptedModel.new(effect, effect, Master::Core::Effect.done("must not finish")),
      constitution: CapabilityLaw.new,
      world: World.new,
      memory:,
      max_turns: 10,
    )

    result = fold.run("connect to Telegram")

    assert_equal :blocked, result.reason
    assert_equal 2, result.turns
    assert_match(/command execution is not enabled in this session/, result.summary)
    assert_match(/no command was run/, result.summary)
    assert_match(/no command was run/, memory.records.first.last.message)
    assert_equal 2, memory.records.length
  end
end
