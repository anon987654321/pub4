# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"

# The design law used to apply only when somebody typed /scan. WriteGuard puts it
# on the write itself, on both paths — Io::Base#commit_write for the tools and an
# injected Constitution rule for the Fold — so the question these answer is what
# a write may introduce, not what a file contains.
class WriteGuardTest < Minitest::Test
  DIRTY = "# frozen_string_literal: true\n\ndef work\n  go\nrescue StandardError\n  nil\nend\n"

  def setup
    @tmp = Dir.mktmpdir("write_guard_test")
    @guard = Master::Review::Scan::WriteGuard.default
  end

  def teardown = FileUtils.remove_entry(@tmp)

  def path(name = "example.rb") = File.join(@tmp, name)

  def test_a_write_that_introduces_an_error_is_blocked
    verdict = @guard.verdict(path: path, content: DIRTY)

    assert_predicate verdict, :blocked?
    assert_match(/SILENT_RESCUE/, verdict.reason)
  end

  # Without this the first repair of any file carrying debt is refused, and the
  # gate that was meant to stop new violations freezes the old ones in place.
  def test_editing_a_file_that_already_carries_the_violation_is_allowed
    File.write(path, DIRTY)

    verdict = @guard.verdict(path: path, content: DIRTY.sub("def work", "def renamed"))

    refute_predicate verdict, :blocked?
    assert_empty verdict.introduced
  end

  def test_a_second_copy_of_an_existing_violation_is_an_introduction
    File.write(path, DIRTY)
    doubled = DIRTY + "\ndef second\n  go\nrescue StandardError\n  nil\nend\n"

    assert_predicate @guard.verdict(path: path, content: doubled), :blocked?
  end

  def test_clean_content_passes
    refute_predicate @guard.verdict(path: path, content: "# frozen_string_literal: true\n\ndef work = 1\n"), :blocked?
  end

  # Semantic rules are 126 of the 225 and cost an LLM call per file. A per-write
  # gate would pay that twice for every write, so the guard holds the mechanical
  # half and the per-turn pass holds the rest.
  def test_semantic_rules_are_not_on_the_write_path
    agent_backed = Master::Review::Scan::InfraHelpers.build_scanner(root: Master::ROOT)
                                                     .rules.select { |rule| rule.respond_to?(:set_agent) }
    refute_empty agent_backed, "the scanner should carry semantic rules for the scan path"

    guarded = Master::Review::Scan::WriteGuard.new(rules: agent_backed)

    assert_empty guarded.verdict(path: path, content: DIRTY).introduced
  end

  # The Fold writes through World rather than through the Io tools, so the same
  # judgement has to be a rule in the Constitution or that lane goes unguarded.
  def test_the_constitution_blocks_a_fold_write_that_introduces_a_violation
    constitution = Master::Core::Constitution.load(data_dir: Master.data_path, verify: verifier)
    memory = Master::Core::Memory.new(risk: :low)
    memory.proof.mark_ideation_complete!

    verdict = constitution.admit(write_effect(DIRTY), memory)

    assert_kind_of Master::Core::Verdict::Block, verdict
    assert_equal :scan_clean, verdict.by
  end

  def test_the_constitution_allows_a_fold_write_with_no_new_violation
    constitution = Master::Core::Constitution.load(data_dir: Master.data_path, verify: verifier)
    memory = Master::Core::Memory.new(risk: :low)
    memory.proof.mark_ideation_complete!

    verdict = constitution.admit(write_effect("# frozen_string_literal: true\n\ndef work = 1\n"), memory)

    assert_kind_of Master::Core::Verdict::Allow, verdict
  end

  def verifier = Master::CLI::CoreBridge.scan_verifier

  def write_effect(content)
    Master::Core::Effect.new(verb: :write, args: { path: path, content: content })
  end
end
