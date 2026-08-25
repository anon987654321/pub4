# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"

require "master"

class TestKernelSpine < Minitest::Test
  Model = Struct.new(:effects) do
    def propose(_context, verbs:)
      raise "missing verbs" unless verbs.include?(:done)

      effects.shift || Master::Core::Effect.done("empty")
    end
  end

  def constitution(sandbox: nil)
    Master::Core::Constitution.load(data_dir: File.expand_path("../../data", __dir__), sandbox:)
  end

  # The hardened shell policy is injected, not required — core reaches nothing in
  # lib/. These pin the seam itself: that an injected denial stops an exec, that
  # the policy's :ask default does not, and that without an injection the fold is
  # left on safe_exec_rule alone, which is what it was before.
  def test_an_injected_sandbox_denial_blocks_the_exec
    denier = ->(argv) { "denied: #{argv.first}" }
    verdict = constitution(sandbox: denier).admit(
      Master::Core::Effect.exec(%w[rm -rf /]), Master::Core::Memory.new
    )

    assert_kind_of Master::Core::Verdict::Block, verdict
    assert_equal :sandboxed_exec, verdict.by
  end

  # The policy answers :ask for anything it does not recognise, which is most
  # commands. If that became a refusal the fold could not run its own tests, so
  # the lambda returns nil and the effect has to survive.
  def test_a_sandbox_that_does_not_deny_lets_the_exec_through
    permissive = ->(_argv) { nil }
    verdict = constitution(sandbox: permissive).admit(
      Master::Core::Effect.exec(%w[bundle exec rake test], evidence: :test_pass), Master::Core::Memory.new
    )

    assert_kind_of Master::Core::Verdict::Allow, verdict
  end

  # The real lambda the CLI hands in, so the seam is pinned against the actual
  # policy rather than a stand-in that could agree with nothing.
  def test_the_wired_sandbox_denies_a_dangerous_rm_and_allows_a_test_run
    sandbox = Master::CLI::CoreBridge.send(:shell_sandbox)

    refute_nil sandbox.call(%w[rm -rf /]), "the hardened policy did not deny a recursive force rm"
    assert_nil sandbox.call(%w[bundle exec rake test]), "the fold cannot run its own tests"
  end

  def test_done_without_evidence_is_blocked
    Dir.mktmpdir do |dir|
      model = Model.new([Master::Core::Effect.done("fake")])
      memory = Master::Core::Memory.new
      world = Master::Core::World.new(root: dir)

      result = Master::Core::Fold.new(
        model:,
        constitution:,
        world:,
        memory:,
        max_turns: 1,
      ).run("finish")

      assert_equal :max_turns, result.reason
      refute memory.proof.proved?
    end
  end

  def test_exec_requires_structured_argv
    effect = Master::Core::Effect.new(verb: :exec, args: { command: "echo unsafe" })
    verdict = constitution.admit(effect, Master::Core::Memory.new)

    assert_kind_of Master::Core::Verdict::Block, verdict
    assert_equal :structured_exec, verdict.by
  end

  def test_batch_delete_of_two_paths_is_blocked
    effect = Master::Core::Effect.exec(%w[rm -rf tmp/a tmp/b])
    verdict = constitution.admit(effect, Master::Core::Memory.new)

    assert_kind_of Master::Core::Verdict::Block, verdict
    assert_equal :batch_delete, verdict.by
  end

  def test_single_path_rm_is_not_a_batch_delete
    assert_nil Master::Core::Constitution.batch_delete_reason(%w[rm -rf tmp/a])
    assert_nil Master::Core::Constitution.batch_delete_reason(%w[git rm -- tmp/a])
  end

  def test_git_clean_without_pathspec_is_batch_delete
    reason = Master::Core::Constitution.batch_delete_reason(%w[git clean -fd])
    assert_match(/git clean/, reason)
  end

  def test_ruby_write_must_parse
    effect = Master::Core::Effect.write("bad.rb", "def nope")
    verdict = constitution.admit(effect, Master::Core::Memory.new)

    assert_kind_of Master::Core::Verdict::Block, verdict
    assert_equal :ruby_parses, verdict.by
  end

  def test_world_blocks_path_escape
    Dir.mktmpdir do |dir|
      world = Master::Core::World.new(root: dir)
      observation = world.perform(Master::Core::Effect.read("../outside"))

      assert observation.err?
      assert_match(/path escapes workspace/, observation.message)
    end
  end

  def test_plain_success_is_not_evidence
    memory = Master::Core::Memory.new
    memory.record(Master::Core::Effect.exec(["true"]), Master::Core::Observation.ok(""))

    refute memory.proof.proved?
  end

  def test_sidecar_markdown_write_is_blocked
    effect = Master::Core::Effect.write("notes.md", "# leftover\n")
    verdict = constitution.admit(effect, Master::Core::Memory.new)

    assert_kind_of Master::Core::Verdict::Block, verdict
    assert_equal :forbidden_file, verdict.by
  end

  def test_single_markdown_that_is_not_forbidden_is_allowed
    assert_nil Master::Core::Constitution.forbidden_file_reason("README.md")
    assert_nil Master::Core::Constitution.forbidden_file_reason("MASTER/lib/core.rb")
  end

  def test_third_top_level_tree_is_scope_creep
    memory = Master::Core::Memory.new
    memory.record(Master::Core::Effect.write("MASTER/a.rb", "x"), Master::Core::Observation.ok("ok"))
    memory.record(Master::Core::Effect.write("RAILS/b.rb", "x"), Master::Core::Observation.ok("ok"))
    verdict = constitution.admit(Master::Core::Effect.write("OPENBSD/c.rb", "x"), memory)

    assert_kind_of Master::Core::Verdict::Block, verdict
    assert_equal :scope_creep, verdict.by
  end

  def test_two_hats_blocks_a_mixed_large_commit
    memory = Master::Core::Memory.new
    memory.record(Master::Core::Effect.write("MASTER/a.rb", "x\n" * 201), Master::Core::Observation.ok("ok"))
    %i[test_pass scan_clean code_review].each do |kind|
      memory.record(Master::Core::Effect.exec(["true"], evidence: kind), Master::Core::Observation.ok("ok"))
    end
    verdict = constitution.admit(
      # paths: because a commit now has to name what it commits — an unscoped one
      # is refused before two_hats ever sees it. This fixture is about the message
      # mixing two hats, so it states a scope and lets that rule do the judging.
      Master::Core::Effect.git(:commit, paths: ["MASTER/a.rb"],
                                        message: "fix the bug and refactor the helper"),
      memory,
    )

    assert_kind_of Master::Core::Verdict::Block, verdict
    assert_equal :two_hats, verdict.by
  end

  def test_two_hats_allows_a_small_mixed_message
    assert_nil Master::Core::Constitution.two_hats_reason("fix the bug and refactor the helper", 20)
  end

  def test_low_risk_new_path_does_not_need_ask
    assert_nil Master::Core::Constitution.new_path_reason("a.rb", Master::Core::Memory.new.proof)
  end
end
