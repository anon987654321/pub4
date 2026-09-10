# frozen_string_literal: true

require_relative "test_helper"
require "review/scan/rule_dsl"

# MASTER-101. Nothing emitted one deterministic answer to "what is in force
# right now": boot_checks.rb proves the files parse, bin/doctor probes the host,
# boot_phases.rb names the order. Three readings, three subjects.
class TestBootReceipt < Minitest::Test
  Receipt = Master::Ground::BootReceipt

  # Deterministic is the whole property. A receipt with a clock in it cannot be
  # diffed against yesterday's, which is the only use it has.
  def test_the_digest_is_stable_across_calls
    assert_equal Receipt.digest, Receipt.digest
    assert_match(/\A[0-9a-f]{16}\z/, Receipt.digest)
  end

  def test_the_receipt_carries_the_constitution_in_force
    constitution = Receipt.build[:constitution]

    assert_equal Master.load_yaml(MasterPaths.data("soul.yml"))["version"], constitution[:soul_version]
    assert_operator constitution[:sacred_paths], :>, 0
  end

  # The three rule populations are allowed to differ — 78 declared rules resolve
  # through a fold and carry no detector. What the receipt must not do is print
  # one of them as the total, which is the misreport it exists to prevent.
  def test_the_receipt_counts_all_three_rule_populations
    law = Receipt.law

    assert_operator law[:declared], :>, 200
    assert_equal Master::Review::Scan::Rule.registry.size, law[:registry]
    assert_includes Receipt.lines.join("\n"), "#{law[:declared]} declared"
  end

  # `schema:` is a version pin sharing the file with the providers. It has no
  # `env`, so it read as a permanently unavailable provider.
  def test_the_provider_row_is_providers_only
    refute_includes Receipt.providers.keys, "schema"
    assert_includes Receipt.providers.keys, "openrouter"
  end

  # MASTER-136 asks for offline as a named capability rather than a mysterious
  # failure. Whatever this host has, the receipt must name the state.
  def test_degraded_capabilities_are_named_not_implied
    line = Receipt.degraded_line(%w[network])

    assert_includes line, "network"
    assert_includes line, "measured less than it claims"
    assert_includes Receipt.capabilities.keys, "network"
    assert_equal "receipt: degraded none", Receipt.degraded_line([])
  end

  # Both shapes of .git, because the tree has two and the runtime mostly runs in
  # the second. A clone keeps a directory; a `git worktree` checkout keeps a file
  # holding one `gitdir:` line, and CLAUDE.md's first trap tells every agent to
  # take a worktree. Four callers tested File.directory? and therefore answered
  # "not a repository" in exactly those trees — rollback after a failed fix went
  # off, the snapshot lost its branch and sha, and this receipt reported git
  # missing while running inside git.
  def test_git_checkout_recognises_a_worktree_as_well_as_a_clone
    Dir.mktmpdir do |dir|
      refute Master.git_checkout?(dir), "an ordinary directory is not a checkout"

      FileUtils.mkdir_p(File.join(dir, ".git"))

      assert Master.git_checkout?(dir), "a clone keeps .git as a directory"
    end

    Dir.mktmpdir do |dir|
      File.write(File.join(dir, ".git"), "gitdir: /elsewhere/.git/worktrees/x\n")

      assert Master.git_checkout?(dir), "a worktree keeps .git as a file"
    end
  end

  # The receipt's own use of it, end to end. `commit` read <root>/../.git/HEAD
  # by hand, which does not resolve when .git is a file, so this suite has only
  # ever run where the answer was "unknown".
  def test_the_receipt_names_the_commit_it_booted_from
    assert_match(/\A[0-9a-f]{12}\z/, Receipt.commit(Master::ROOT))
    assert Receipt.capabilities["git"], "the receipt is running inside a checkout"
  end
end
