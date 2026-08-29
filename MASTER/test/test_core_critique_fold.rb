# frozen_string_literal: true

require "minitest/autorun"
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "result"
require "master"

class CritiqueFoldTest < Minitest::Test
  class ScriptedModel
    def initialize(*effects) = @effects = effects
    def propose(_context, verbs:) = @effects.shift || Master::Core::Effect.done("shipped")
  end

  def constitution
    Master::Core::Constitution.load(data_dir: File.expand_path("../data", __dir__))
  end

  def test_critique_effect_records_council_pass
    memory = Master::Core::Memory.new(risk: :high)
    memory.proof.mark_ideation_complete!
    runner = lambda do |**_|
      Master::Result.ok("critique: council pass")
    end
    world = Master::Core::World.new(root: Dir.mktmpdir, critique_runner: runner)
    observation = world.perform(Master::Core::Effect.critique)
    memory.record(Master::Core::Effect.critique, observation)

    assert memory.proof.council_cleared?
  end

  def test_high_risk_fold_completes_with_critique
    Dir.mktmpdir do |root|
      memory = Master::Core::Memory.new(risk: :high)
      memory.note(:goal, "ship fix")
      memory.proof.mark_ideation_complete!
      # Evidence is seeded rather than executed. This Fold runs against a real
      # World in a tmpdir, so a scripted `bundle exec rake test` really would be
      # spawned there, fail, and record nothing — and ["true"], which used to
      # stand in, no longer earns anything now that a kind has to name a command
      # that could produce it. The subject here is critique-before-done, so the
      # proof arrives the same way the spine test arranges it.
      { test_pass: %w[bundle exec rake test], scan_clean: %w[bin/check],
        code_review: %w[bin/review] }.each do |kind, argv|
        memory.record(Master::Core::Effect.exec(argv, evidence: kind), Master::Core::Observation.ok("ok"))
      end
      model = ScriptedModel.new(
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
