# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"

require "master"

class TestKernelSpine < Minitest::Test
  Model = Struct.new(:effects) do
    def propose(_context, verbs:, **)
      raise "missing verbs" unless verbs.include?(:done)

      effects.shift || Master::Core::Effect.done("empty")
    end
  end

  def constitution(sandbox: nil)
    Master::Core::Constitution.load(data_dir: File.expand_path("../data", __dir__), sandbox:)
  end

  # A question asked of the code: the fold reads and answers, and done is not a
  # claim about a changed tree. A fold that acted still needs evidence.
  def test_a_fold_that_only_read_may_answer
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "notes.md"), "hello\n")
      read = Master::Core::Effect.new(verb: :read, args: { path: "notes.md" })

      answered = fold_in(dir, [read, Master::Core::Effect.done("it says hello")])
      acted = fold_in(dir, [read, Master::Core::Effect.exec(%w[echo hi]), Master::Core::Effect.done("done")])

      assert_equal :complete, answered.reason
      assert_equal :max_turns, acted.reason
    end
  end

  def fold_in(dir, effects)
    Master::Core::Fold.new(model: Model.new(effects), constitution:, world: Master::Core::World.new(root: dir),
                           memory: Master::Core::Memory.new, max_turns: 3).run("what does notes.md say")
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

  # A long command output keeps its first and last lines, and a short one
  # arrives whole.
  def test_a_long_exec_result_keeps_its_head_and_tail
    memory = Master::Core::Memory.new
    output = "FIRST ERROR\n#{"x" * 20_000}\n12 runs, 0 failures"
    memory.record(Master::Core::Effect.exec(%w[rake test]), Master::Core::Observation.ok(output))
    memory.record(Master::Core::Effect.exec(%w[true]), Master::Core::Observation.ok("short"))

    long, short = memory.context.select { |entry| entry.role == :obs }.map(&:text)
    assert_operator long.length, :<, 1_600
    assert long.start_with?("ok: FIRST ERROR"), long[0, 40]
    assert long.end_with?("12 runs, 0 failures"), long[-40..]
    assert_equal "ok: short", short
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

  # The repo root holds three governed trees. A bin/ or dotfiles/ segment sits inside one
  # of them, so a MASTER-relative bin/ write is not a fourth tree.
  def test_a_bin_segment_is_not_a_tree
    memory = Master::Core::Memory.new
    memory.record(Master::Core::Effect.write("MASTER/a.rb", "x"), Master::Core::Observation.ok("ok"))
    memory.record(Master::Core::Effect.write("RAILS/b.rb", "x"), Master::Core::Observation.ok("ok"))

    assert_nil Master::Core::Constitution.scope_creep_reason("bin/check", memory.proof)
    assert_nil Master::Core::Constitution.scope_creep_reason("dotfiles/zshrc", memory.proof)
  end

  def test_two_hats_blocks_a_mixed_large_commit
    memory = Master::Core::Memory.new
    memory.record(Master::Core::Effect.write("MASTER/a.rb", "x\n" * 201), Master::Core::Observation.ok("ok"))
    # A command that can actually produce each kind. ["true"] used to stand in for
    # all three, which PRODUCERS now scores at zero — the fixture would reach
    # git_commit_evidence instead of the rule it is about.
    { test_pass: %w[bundle exec rake test], scan_clean: %w[bin/check],
      code_review: %w[bin/review] }.each do |kind, argv|
      memory.record(Master::Core::Effect.exec(argv, evidence: kind), Master::Core::Observation.ok("ok"))
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
