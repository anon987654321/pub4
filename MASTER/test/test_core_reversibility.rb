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

  def test_every_effect_verb_has_an_explicit_capability_and_recovery_classification
    effects = [
      E.read("a.rb"),
      E.write("a.rb", "A = 1"),
      E.exec(%w[ruby -v]),
      E.git(:diff),
      E.http("https://example.com"),
      E.ask("continue?"),
      E.note(:idea, "inspect first"),
      E.critique,
      E.done("answer"),
    ]
    by_verb = effects.to_h { |effect| [effect.verb, effect] }

    assert_equal Master::Core::VERBS.sort, by_verb.keys.sort
    assert_equal(
      {
        read: :read, write: :write, exec: :execute, git: :read, http: :network,
        ask: :stdio, note: :stdio, critique: :stdio, done: :stdio
      },
      by_verb.transform_values(&:capability),
    )
    assert_equal(
      {
        read: :non_mutating, write: :reversible, exec: :policy_gated, git: :non_mutating,
        http: :policy_gated, ask: :non_mutating, note: :session_state,
        critique: :non_mutating, done: :non_mutating
      },
      by_verb.transform_values { |effect| effect.reversibility.kind },
    )
    assert_equal :write, E.git(:status).capability
    assert_equal :unknown, E.git(:status).reversibility.kind
    assert_equal :unknown, E.git(:reset).reversibility.kind
  end

  def test_an_approval_request_cannot_skip_a_later_constitutional_block
    effect = E.exec(%w[ruby -v])
    request = C::Law.new(id: :needs_approval, verbs: [:exec], judge: lambda { |candidate, _memory|
      Master::Core::Verdict::Request.new(
        effect: candidate, prompt: "approve command?", reason: "test request", by: :needs_approval,
      )
    })
    blocker = C::Law.new(id: :hostile_condition, verbs: [:exec], judge: lambda { |_candidate, _memory|
      Master::Core::Verdict::Block.new(reason: "hostile fixture refused", by: :hostile_condition)
    })
    world = RecordingWorld.new(answer: "yes")
    fold = Master::Core::Fold.new(
      model: ScriptedModel.new(effect, effect, effect),
      constitution: C.new(laws: [request, blocker]),
      world:,
      memory: Master::Core::Memory.new,
      max_turns: 3,
    )

    result = fold.run("exercise the approval boundary")

    assert_equal :blocked, result.reason
    assert_empty world.performed, "neither the approval prompt nor the blocked effect may reach World"
  end

  def test_all_approval_requirements_are_carried_through_the_full_law_chain
    first = C::Law.new(id: :first_check, verbs: [:exec], judge: lambda { |effect, _memory|
      Master::Core::Verdict::Request.new(
        effect:, prompt: "first check required", reason: "first reason", by: :first_check,
      )
    })
    second = C::Law.new(id: :second_check, verbs: [:exec], judge: lambda { |effect, _memory|
      Master::Core::Verdict::Request.new(
        effect:, prompt: "second check required", reason: "second reason", by: :second_check,
      )
    })

    verdict = C.new(laws: [first, second]).admit(E.exec(%w[ruby -v]), Master::Core::Memory.new)

    assert_instance_of Master::Core::Verdict::Request, verdict
    assert_equal :multiple_constitutional_checks, verdict.by
    assert_includes verdict.prompt, "first check required"
    assert_includes verdict.prompt, "second check required"
    assert_includes verdict.reason, "first reason"
    assert_includes verdict.reason, "second reason"
  end

  def test_contract_is_derived_from_effect_type_and_operation
    assert_equal :non_mutating, E.read("a.rb").reversibility.kind
    assert_equal :reversible, E.write("a.rb", "A = 1").reversibility.kind
    assert_equal :scoped_checkpoint_restore, E.write("a.rb", "A = 1").reversibility.compensation
    assert_equal :policy_gated, E.exec(%w[ruby -v]).reversibility.kind
    assert_equal :policy_gated, E.http("https://example.com").reversibility.kind
    assert_equal :approval_required, E.git(:stage, paths: ["a.rb"]).reversibility.kind
    assert_equal :approval_required, E.git(:commit, paths: ["a.rb"]).reversibility.kind
    assert_predicate E.git(:commit, paths: ["a.rb"]).reversibility, :approval_required?
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

  def test_effect_payload_is_copied_and_frozen_before_admission
    argv = %w[ruby -v]
    env = { "LABEL" => "before" }
    source = { argv:, env: }
    effect = E.new(verb: :exec, args: source)

    argv << "unapproved"
    env["LABEL"] = "after"
    source[:extra] = "late mutation"

    assert_equal %w[ruby -v], effect.args[:argv]
    assert_equal "before", effect.args[:env]["LABEL"]
    refute effect.args.key?(:extra)
    assert_raises(FrozenError) { effect.args[:argv] << "unapproved" }
    assert_raises(FrozenError) { effect.args[:env]["LABEL"] = "after" }
  end

  def test_the_model_cannot_assign_its_own_reversibility
    effect = E.new(verb: :exec, args: { argv: %w[ruby -v], reversibility: "reversible" })

    assert_equal :policy_gated, effect.reversibility.kind
  end

  def test_model_schema_declares_compensation_as_structured_argv
    schema = Master::Core::Model.schema.dig(:properties, :args, :properties, :compensation)

    assert_equal %w[argv reason], schema[:required]
    assert_equal false, schema[:additionalProperties]
    assert_equal "array", schema.dig(:properties, :argv, :type)
    assert_equal "string", schema.dig(:properties, :reason, :type)
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
    reply = <<~JSON
      {"verb":"exec","args":{"argv":["perform","partial"],
       "compensation":{"argv":["undo","partial"],"reason":"restore prior state"}}}
    JSON
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
    assert_match(/no reversibility contract or World handler/, verdict.reason)
  end

  def test_unscoped_stage_is_blocked_instead_of_prompting_for_approval
    effect = E.git(:stage)
    verdict = C.load(data_dir: DATA_DIR).admit(effect, Master::Core::Memory.new)

    assert_equal :unknown, effect.reversibility.kind
    assert_instance_of Master::Core::Verdict::Block, verdict
    assert_equal :effect_reversibility, verdict.by
    assert_match(/requires explicit paths/, verdict.reason)
  end

  def test_commit_requests_approval_only_after_its_evidence_check_passes
    memory = Master::Core::Memory.new
    [
      E.exec(%w[rake test], evidence: :test_pass),
      E.exec(%w[bin/check], evidence: :scan_clean),
      E.exec(%w[bin/review], evidence: :code_review),
    ].each { |effect| memory.record(effect, Master::Core::Observation.ok("verified")) }
    assert memory.proof.proved?, "fixture evidence must satisfy the commit precondition"

    verdict = C.load(data_dir: DATA_DIR).admit(
      E.git(:commit, message: "add verified work", paths: ["a.rb"]),
      memory,
    )

    assert_instance_of Master::Core::Verdict::Request, verdict
    assert_equal :effect_reversibility, verdict.by
    assert_match(/durable repository history/, verdict.reason)
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
    lifecycle = []
    effect_observer = lambda do |stage:, effect_id:, operation:, parent_effect_id: nil, **|
      lifecycle << { stage:, effect_id:, operation:, parent_effect_id: }
    end
    fold = Master::Core::Fold.new(
      model: ScriptedModel.new(effect),
      constitution: C.new(laws: []),
      world:,
      memory: Master::Core::Memory.new,
      max_turns: 1,
      observer: ->(turn:, effect:, observation:) { seen << observation },
      effect_observer:,
    )

    fold.run("perform a compensatable operation")

    assert_equal %i[exec ask exec], world.performed.map(&:verb)
    assert_equal %w[undo partial], world.performed.last.args[:argv]
    refute seen.fetch(0).ok?
    assert_match(/exit 1 after partial application/, seen.fetch(0).message)
    assert_match(/compensation completed/, seen.fetch(0).message)
    assert_equal [
      [:before, :perform], [:after, :perform],
      [:before, :compensation_approval], [:after, :compensation_approval],
      [:before, :compensation], [:after, :compensation]
    ], lifecycle.map { |event| [event[:stage], event[:operation]] }
    original_id = lifecycle.first.fetch(:effect_id)
    assert_equal original_id, lifecycle[2].fetch(:parent_effect_id)
    assert_equal original_id, lifecycle[4].fetch(:parent_effect_id)
    refute_equal original_id, lifecycle[4].fetch(:effect_id)
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
