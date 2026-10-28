# frozen_string_literal: true

require "minitest/autorun"
require "pathname"
require_relative "../lib/execution/contract"

class NoLibBackedgesTest < Minitest::Test
  # Scoped to the class: three files in one test process defined a top-level
  # ROOT, one of them a String, and load order picked the winner.
  ROOT = Pathname.new(__dir__).join("..").expand_path
  LIB = ROOT.join("lib")
  # The fold spine shares lib/ and one Zeitwerk loader with the application
  # spine, so no directory boundary keeps the dependency pointing one way. This
  # test is that boundary: it names the fold's files, lib/core.rb and
  # lib/core/**, and proves none of them requires a sibling under lib/.
  #
  # It reads `require` lines, so an autoloaded constant slips past it. That is
  # why Core::Constitution.load calls YAML.safe_load_file on data/laws.yml
  # itself instead of Master.load_laws: the loader lives in lib/boot/data_loading.rb,
  # needs no require to reach, and calling it makes the fold's first backedge. The two
  # reads return the same object; the loader adds a size limit, a timeout and
  # permitted classes, and laws.yml holds no Date, which keeps them equal.
  CORE = [LIB.join("core.rb"), *LIB.join("core").glob("**/*.rb")].freeze

  def test_core_files_do_not_require_lib
    offenders = []
    CORE.each do |path|
      text = path.read
      next unless text.match?(/\b(require|require_relative)\b/)

      text.each_line.with_index(1) do |line, lineno|
        next unless line.match?(/^\s*(require|require_relative)\s+["']/)
        # Its own core namespace and the stdlib are fine; a sibling under the
        # rest of lib/ is not.
        if (relative = line.match(/^\s*require_relative\s+["']([^"']+)["']/))
          target = path.dirname.join(relative[1]).expand_path
          next if target == LIB.join("core") || target.to_s.start_with?("#{LIB.join("core")}#{File::SEPARATOR}")
        end
        next if line.match?(/["'](open3|prism|yaml|json|ruby_llm|tmpdir|fileutils|timeout|securerandom|rbconfig|pathname|shellwords|set|time|digest|open-uri|uri|net\/http|etc|io\/console)["']/)

        offenders << "#{path.relative_path_from(ROOT)}:#{lineno}: #{line.strip}"
      end
    end

    assert_empty offenders, "lib/core (the fold spine) must not require the rest of lib/:\n#{offenders.join("\n")}"
  end

  def test_effect_fold_keeps_policy_io_memory_and_proof_responsibilities_separate
    fold = LIB.join("core/fold.rb").read
    constitution = LIB.join("core/constitution.rb").read
    world = LIB.join("core/world.rb").read
    memory = LIB.join("core/memory.rb").read
    proof = LIB.join("core/proof.rb").read

    assert_includes fold, "@law.admit(effect, @memory)"
    assert_includes fold, "@world.perform"
    assert_includes fold, "@memory.record(effect, observation)"
    assert_includes fold, "@world.checkpoint"
    assert_includes fold, "@world.rollback"

    assert_includes constitution, "def admit(effect, memory)"
    assert_includes constitution, "Verdict::Block"
    assert_includes world, "def perform(effect)"
    assert_includes world, "@capabilities.require!(effect.capability)"
    assert_includes memory, "def record(effect, observation)"
    assert_includes memory, "@proof.record_evidence(effect, observation)"
    assert_includes proof, "PRODUCERS ="
    assert_includes proof, "PASS_THRESHOLD = 80"
  end

  def test_repository_repair_loop_remains_distinct_from_the_effect_fold
    fix_loop = ROOT.join("lib/fix/fix_loop.rb").read
    convergence = ROOT.join("lib/fix/kernel/convergence_adapter.rb").read
    kernel = ROOT.join("lib/fix/kernel.rb").read
    lifecycle = ROOT.join("lib/fix/kernel/lifecycle.rb").read
    journal_adapter = ROOT.join("lib/fix/run_journal.rb").read
    protocol = ROOT.join("lib/fix/protocol.rb").read

    assert_includes fix_loop, 'require_relative "kernel/convergence_adapter"'
    refute_includes fix_loop, "class FixLoop"
    assert_includes convergence, "class ConvergenceAdapter"
    assert_includes convergence, 'require_relative "../kernel"'
    assert_includes convergence, 'require_relative "../protocol"'
    assert_includes kernel, 'require_relative "kernel/lifecycle_journal"'
    assert_includes lifecycle, "def run_fix_loop"
    assert_includes lifecycle, "def lifecycle_journal"
    assert_includes journal_adapter, 'require_relative "kernel"'
    assert_includes convergence, 'require_relative "../protocol"'
    # Protocol derives its terminal states from the shared execution vocabulary
    # through OutcomePolicy, so the states are proved on that vocabulary.
    assert_includes protocol, "TERMINAL_STATES = OutcomePolicy::TERMINAL_STATES"
    states = Master::Execution::Contract::TERMINAL_STATES
    %i[done plateau human_decision blocked inconclusive validation_failed delivery_failed
       timeout failed reloading].each do |state|
      assert_includes states, state
    end
  end

  def test_canonical_constitutional_sources_remain_required
    soul_path = ROOT.join("data/soul.yml")
    laws_path = ROOT.join("data/laws.yml")
    contract_path = ROOT.join("lib/operator/constitution_contract.rb")

    assert soul_path.file?, "the canonical soul data must remain present"
    assert laws_path.file?, "the canonical law catalogue must remain present"
    assert_includes soul_path.read, "PRESERVE_THEN_IMPROVE_NEVER_BREAK"
    contract = contract_path.read
    assert_includes contract, "MASTER/data/soul.yml"
    assert_includes contract, "MASTER/data/laws.yml"
  end

  def test_the_fold_spine_is_actually_being_looked_at
    refute_empty CORE, "no fold-spine files found — this test would pass having measured nothing"
    assert_includes CORE.map { |p| p.basename.to_s }, "fold.rb"
  end
end
