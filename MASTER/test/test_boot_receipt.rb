# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "review/scan/law_tree"

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

  # Normative rows, per-Law policy entries and the loaded detector registry
  # are distinct populations, all read from their current source owner.
  def test_the_receipt_counts_normative_rows_catalogue_entries_and_registry
    law = Receipt.law

    assert_operator law[:normative], :>, 100
    assert_operator law[:catalogue], :>, 200
    assert_equal Master::law_entries(root: Master::ROOT).size, law[:normative]
    assert_equal Master.law_catalogue(root: Master::ROOT).fetch("entries").size, law[:catalogue]
    assert_equal Master::Review::Scan::LawTree.ids.size, law[:registry]
    output = Receipt.lines.join("\n")
    assert_includes output, "normative=#{law[:normative]}"
    assert_includes output, "catalogue=#{law[:catalogue]}"
    refute_includes output, "legacy_metadata="
  end

  # `schema:` is a version pin sharing the file with the providers. It has no
  # `env`, so it read as a permanently unavailable provider.
  def test_the_provider_row_is_providers_only
    refute_includes Receipt.providers.keys, "schema"
    assert_includes Receipt.providers.keys, "openrouter"
  end

  # MASTER-136 asks for offline as a named capability rather than a mysterious
  # failure. Whatever this host has, the receipt must name the state.
  def test_tts_capability_uses_the_runtime_backend_guard
    Master::Voice::Speech.stub(:available?, true) do
      assert Receipt.capabilities["tts"]
    end
    Master::Voice::Speech.stub(:available?, false) do
      refute Receipt.capabilities["tts"]
    end
  end

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
  def test_domain_law_count_resolves_laws_from_repository_root
    count = Receipt.domain_law_count(Master::REPO_ROOT)

    assert_operator count, :>, 100
  end

  def test_session_receipt_is_empty_without_runtime_context
    assert_equal({}, Receipt.session)
    refute Receipt.lines.any? { |line| line.start_with?("receipt: session ") }
  end

  def test_session_receipt_joins_commit_memory_and_model
    memory = Struct.new(:version).new(17)
    agent = Struct.new(:model).new("test-model")

    receipt = Receipt.session(root: Master::ROOT, agent:, memory:)

    assert_equal checkout_commit, receipt.fetch(:commit)
    assert_equal 17, receipt.fetch(:memory_version)
    assert_equal "test-model", receipt.fetch(:model)
    assert_equal Receipt.digest, receipt.fetch(:constitution)
  end

  def test_session_line_is_operator_readable
    line = Receipt.session_line(
      commit: "abc123def456",
      constitution: "0123456789abcdef",
      memory_version: 3,
      model: "test-model",
    )

    assert_equal(
      "receipt: session commit=abc123def456 constitution=0123456789abcdef memory=3 model=test-model",
      line,
    )
  end

  def test_session_receipt_builds_without_changing_plain_doctor_lines
    memory = Struct.new(:version).new(4)
    agent = Struct.new(:model).new("test-model")
    receipt = Receipt.build(root: Master::ROOT, agent:, memory:)

    assert_equal 4, receipt.fetch(:session).fetch(:memory_version)
    assert_includes Receipt.session_line(receipt.fetch(:session)), "memory=4"
    refute Receipt.lines(root: Master::ROOT).any? { |line| line.start_with?("receipt: session ") }
  end

  # In a checkout the receipt names HEAD; in a git archive export (where the
  # suite is proved) there is no HEAD and it says unknown rather than guess.
  def test_the_receipt_names_the_commit_it_booted_from
    commit = Receipt.commit(Master::ROOT)

    assert_equal checkout_commit, commit
    assert_match(/\A(?:[0-9a-f]{12}|unknown)\z/, commit)
  end

  private

  def checkout_commit
    out, status = Open3.capture2e("git", "-C", Master::ROOT, "rev-parse", "--short=12", "HEAD")
    status.success? ? out.strip : "unknown"
  end
end
