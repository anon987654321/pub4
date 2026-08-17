# frozen_string_literal: true

require "minitest/autorun"
$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "master"
require "cli/fold_risk"

class FoldDeliberationTest < Minitest::Test
  class ScriptedModel
    def initialize(*effects) = @effects = effects
    def propose(_context, verbs:) = @effects.shift || Master::Core::Effect.done("done")
  end

  def evidence_effects
    [
      Master::Core::Effect.exec(["true"], evidence: :test_pass),
      Master::Core::Effect.exec(["true"], evidence: :scan_clean),
      Master::Core::Effect.exec(["true"], evidence: :code_review),
    ]
  end

  def test_high_risk_blocks_done_without_critique
    memory = Master::Core::Memory.new(risk: :high)
    memory.note(:goal, "ship it")
    evidence_effects.each { |effect| memory.record(effect, Master::Core::Observation.ok("ok")) }

    law = Master::Core::Constitution.load(data_dir: File.expand_path("../../data", __dir__))
    verdict = law.admit(Master::Core::Effect.done("shipped"), memory)

    assert_instance_of Master::Core::Verdict::Block, verdict
    assert_match(/critique/, verdict.reason)
  end

  def test_critique_clears_council_gate
    memory = Master::Core::Memory.new(risk: :high)
    memory.record(Master::Core::Effect.critique, Master::Core::Observation.ok("council pass"))

    assert memory.proof.council_cleared?
  end

  def test_ideation_blocks_write_when_unsatisfied
    memory = Master::Core::Memory.new(risk: :medium)
    law = Master::Core::Constitution.load(data_dir: File.expand_path("../../data", __dir__))
    verdict = law.admit(Master::Core::Effect.write("a.rb", "x"), memory)

    assert_instance_of Master::Core::Verdict::Block, verdict
    assert_match(/ideation/, verdict.reason)
  end

  def test_ideation_seeded_allows_write
    memory = Master::Core::Memory.new(risk: :medium)
    memory.note(:chosen, "use option 2")
    memory.proof.mark_ideation_complete!
    law = Master::Core::Constitution.load(data_dir: File.expand_path("../../data", __dir__))
    verdict = law.admit(Master::Core::Effect.write("a.rb", "x"), memory)

    assert_instance_of Master::Core::Verdict::Allow, verdict
  end

  def test_fourteen_approaches_do_not_satisfy_ideation
    memory = Master::Core::Memory.new(risk: :medium)
    memory.proof.mark_ideation_complete!(approaches: 14)
    law = Master::Core::Constitution.load(data_dir: File.expand_path("../../data", __dir__))
    verdict = law.admit(Master::Core::Effect.write("a.rb", "x"), memory)

    assert_instance_of Master::Core::Verdict::Block, verdict
    assert_match(/ideation/, verdict.reason)
  end

  def test_fifteen_approaches_satisfy_ideation
    memory = Master::Core::Memory.new(risk: :medium)
    memory.proof.mark_ideation_complete!(approaches: 15)
    law = Master::Core::Constitution.load(data_dir: File.expand_path("../../data", __dir__))
    verdict = law.admit(Master::Core::Effect.write("a.rb", "x"), memory)

    assert_instance_of Master::Core::Verdict::Allow, verdict
  end

  def test_fold_risk_assess_bumps_ship_to_high
    assessment = Master::CLI::FoldRisk.assess("commit the auth fix")
    assert_equal :high, assessment[:risk]
  end
end
