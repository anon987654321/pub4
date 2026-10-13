# frozen_string_literal: true

require "minitest/autorun"
require "master"
require "tmpdir"

# Reversibility is executable policy, not a model-supplied label. These tests
# cover the contract, the approval boundary, and the only supported compensation
# path: a separately admitted argv command after a failed exec.
class TestCoreReversibility < Minitest::Test
  E = Master::Core::Effect
  C = Master::Core::Constitution
  DATA_DIR = File.expand_path("../data", __dir__)

  class ScriptedModel
    def initialize(*effects) = @effects = effects
    def propose(_context, **)
      @effects.shift || E.done("script exhausted")
    end
  end

  class RecordingWorld
    attr_reader :performed

    def initialize(answer: "yes")
      @answer = answer
      @performed = []
    end

    def verbs = Master::Core::VERBS

    def perform(effect)
      @performed << effect
      case effect.verb
      when :ask
        Master::Core::Observation.ok(@answer)
      when :exec
        if effect.args[:argv] == %w[perform partial]
          Master::Core::Observation.no("exit 1 after partial application")
        else
          Master::Core::Observation.ok("inverse ran")
        end
      else
        Master::Core::Observation.no("unexpected effect: #{effect.verb}")
      end
    end
  end

  def test_contract_is_derived_from_effect_type_and_operation
    assert_equal :non_mutating, E.read("a.rb").reversibility.kind
    assert_equal :reversible, E.write("a.rb", "A = 1").reversibility.kind
    assert_equal :scoped_checkpoint_restore, E.write("a.rb", "A = 1").reversibility.compensation
    assert_equal :policy_gated, E.exec(%w[ruby -v]).reversibility.kind
    assert_equal :policy_gated, E.http("https://example.com").reversibility.kind
    assert_equal :approval_required, E.git(:stage, paths: ["a.rb"]).reversibility.kind
    assert_equal :approval_required, E.git(:commit, paths: ["a.rb"]).reversibility.kind
    assert_equal :unknown, E.git(:reset).reversibility.kind
  end

  def test_compensating_action_is_typed_and_requires_a_reason
    effect = E.exec(
      %w[perform partial],
      compensation: { argv: %w[undo partial], reason: "restore the prior external state" },
    )
    contract = effect.reversibility

    assert_equal :compensatable, contract.kind
    assert_instance_of Master::Core::CompensatingAction, contract.compensation
    assert_equal %w[undo partial], contract.compensation.argv
    assert_equal "restore the prior external state", contract.compensation.reason
  end

  def test_malformed_compensation_is_rejected_at_effect_construction
    assert_raises(ArgumentError) do
      E.exec(%w[perform partial], compensation: { argv: %w[undo partial] })
    end
    assert_raises(ArgumentError) do
      E.exec(%w[perform partial], compensation: { argv: %w[undo partial], reason: "undo", shell: true })
    end
  end

  def test_model_parse_preserves_structured_compensation
    reply = %({"verb":"exec","args":{"argv":["perform","partial"],"compensation":{"argv":["undo","partial"],"reason":"restore prior state"}}})
    effect = Master::Core::Model.parse(reply, verbs: Master::Core::VERBS)

    assert_equal :exec, effect.verb
    assert_equal :compensatable, effect.reversibility.kind
    assert_equal %w[undo partial], effect.reversibility.compensation.argv
  end

  def test_irreversible_git_mutation_returns_an_approval_request
    constitution = C.load(data_dir: DATA_DIR)
    verdict = constitution.admit(E.git(:stage, paths: ["new.rb"]), Master::Core::Memory.new)

    assert_instance_of Master::Core::Verdict::Request, verdict
    assert_equal :effect_reversibility, verdict.by
    assert_match(/shared index/, verdict.reason)
    assert_match(/Approve git stage on new.rb/, verdict.prompt)
  end

  def test_git_operation_without_a_world_handler_is_blocked
    verdict = C.load(data_dir: DATA_DIR).admit(E.git(:reset), Master::Core::Memory.new)

    assert_instance_of Master::Core::Verdict::Block, verdict
    assert_equal :effect_reversibility, verdict.by
    assert_match(/no World handler/, verdict.reason)
  end

  def test_irreversible_git_mutation_does_not_reach_world_without_operator
    Dir.mktmpdir do |root|
      world = Class.new(Master::Core::World) do
        attr_reader :performed

        def initialize(**options)
          super
          @performed = []
        end

        def perform(effect)
          @performed << effect
          super
        end
      end.new(root:)
      model = ScriptedModel.new(E.git(:stage, paths: ["new.rb"]))
      fold = Master::Core::Fold.new(
        model:,
        constitution: C.load(data_dir: DATA_DIR),
        world:,
        memory: Master::Core::Memory.new,
      )

      result = fold.run("stage a new file")

      assert_equal :needs_user, result.reason
      refute world.performed.any? { |effect| effect.verb == :git },
             "the Git mutation ran without an operator answer"
    end
  end

  def test_failed_exec_runs_only_approved_and_re_admitted_compensation
    effect = E.exec(
      %w[perform partial],
      compensation: { argv: %w[undo partial], reason: "restore the prior external state" },
    )
    world = RecordingWorld.new
    seen = []
    fold = Master::Core::Fold.new(
      model: ScriptedModel.new(effect),
      constitution: C.new(laws: []),
      world:,
      memory: Master::Core::Memory.new,
      max_turns: 1,
      observer: ->(turn:, effect:, observation:) { seen << observation },
    )

    fold.run("perform a compensatable operation")

    assert_equal %i[exec ask exec], world.performed.map(&:verb)
    assert_equal %w[undo partial], world.performed.last.args[:argv]
    refute seen.fetch(0).ok?
    assert_match(/exit 1 after partial application/, seen.fetch(0).message)
    assert_match(/compensation completed/, seen.fetch(0).message)
  end

  def test_declined_compensation_never_runs_the_inverse
    effect = E.exec(
      %w[perform partial],
      compensation: { argv: %w[undo partial], reason: "restore the prior external state" },
    )
    world = RecordingWorld.new(answer: "no")
    seen = []
    fold = Master::Core::Fold.new(
      model: ScriptedModel.new(effect),
      constitution: C.new(laws: []),
      world:,
      memory: Master::Core::Memory.new,
      max_turns: 1,
      observer: ->(turn:, effect:, observation:) { seen << observation },
    )

    fold.run("perform a compensatable operation")

    assert_equal %i[exec ask], world.performed.map(&:verb)
    refute world.performed.any? { |performed| performed.args[:argv] == %w[undo partial] }
    assert_match(/compensation not run: operator declined/, seen.fetch(0).message)
  end
end
