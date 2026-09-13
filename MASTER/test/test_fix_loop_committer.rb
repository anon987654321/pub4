# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"

# The fix-loop committer commits only what its own pass changed: never a path
# that was already dirty when the pass began, never the shared index, and never
# a tree where an autofix left Ruby unparseable.
class TestFixLoopCommitter < Minitest::Test
  class FakeBus
    attr_reader :events

    def initialize
      @events = []
    end

    def publish(event, payload = {})
      @events << [event, payload]
    end
  end

  # changed_paths answers the baseline first, then the tree after the pass.
  class FakeGit
    attr_reader :commits

    def initialize(before, after)
      @answers = [before, after]
      @commits = []
    end

    def changed_paths
      @answers.size > 1 ? @answers.shift : @answers.first
    end

    def commit(message, paths:)
      @commits << [message, paths]
    end

    def head = "abc1234"
  end

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir)
  end

  def write_file(rel, src)
    path = File.join(@dir, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, src)
  end

  def run_committer(git, bus, message, baseline: true)
    committer = Master::Fix::FixLoop::Committer.new(git:, bus:, root: @dir)
    committer.baseline! if baseline
    committer.commit_if_dirty(message)
  end

  def blocked?(bus)
    bus.events.any? { |event, _payload| event == "fix_loop:commit_blocked" }
  end

  def test_commits_when_changed_ruby_parses
    write_file("lib/ok.rb", "FOO = {\n  a: 1,\n}.freeze\n")
    git = FakeGit.new([], ["lib/ok.rb"])
    bus = FakeBus.new
    run_committer(git, bus, "fix: ok")
    assert_equal [["fix: ok", ["lib/ok.rb"]]], git.commits
    refute blocked?(bus)
  end

  def test_blocks_commit_on_freeze_corruption
    write_file("lib/bad.rb", "FOO = {.freeze\n  a: 1,\n}.freeze\n")
    git = FakeGit.new([], ["lib/bad.rb"])
    bus = FakeBus.new
    run_committer(git, bus, "fix: bad")
    assert_empty git.commits
    assert blocked?(bus)
  end

  def test_blocks_commit_on_missing_end
    write_file("lib/bad2.rb", "def m\n  if x\n  end\n")
    git = FakeGit.new([], ["lib/bad2.rb"])
    bus = FakeBus.new
    run_committer(git, bus, "fix: bad2")
    assert_empty git.commits
    assert blocked?(bus)
  end

  def test_ignores_non_ruby_changes
    write_file("README.md", "# hi\n")
    git = FakeGit.new([], ["README.md"])
    bus = FakeBus.new
    run_committer(git, bus, "docs: update")
    assert_equal [["docs: update", ["README.md"]]], git.commits
    refute blocked?(bus)
  end

  def test_a_path_dirty_before_the_pass_stays_out_of_the_commit
    write_file("lib/ok.rb", "OK = 1\n")
    git = FakeGit.new(["lib/theirs.rb"], ["lib/theirs.rb", "lib/ok.rb"])
    run_committer(git, FakeBus.new, "fix: ok")
    assert_equal [["fix: ok", ["lib/ok.rb"]]], git.commits
  end

  # Another session's unparseable half-edit must neither be committed nor block
  # the pass's own commit.
  def test_foreign_broken_ruby_does_not_block_the_pass
    write_file("lib/theirs.rb", "def m\n")
    write_file("lib/ok.rb", "OK = 1\n")
    git = FakeGit.new(["lib/theirs.rb"], ["lib/theirs.rb", "lib/ok.rb"])
    bus = FakeBus.new
    run_committer(git, bus, "fix: ok")
    assert_equal [["fix: ok", ["lib/ok.rb"]]], git.commits
    refute blocked?(bus)
  end

  def test_the_body_names_the_findings_in_committed_files
    write_file("lib/ok.rb", "OK = 1\n")
    git = FakeGit.new(["lib/theirs.rb"], ["lib/theirs.rb", "lib/ok.rb"])
    findings = [
      { rule: "NO_PUTS", file: "lib/ok.rb", line: 3 },
      { rule: "LONG_LINE", file: File.join(@dir, "lib/ok.rb"), line: 9 },
      { rule: "NO_PUTS", file: "lib/theirs.rb", line: 1 },
    ]
    committer = Master::Fix::FixLoop::Committer.new(git:, bus: FakeBus.new, root: @dir)
    committer.baseline!
    committer.commit_if_dirty("fix_loop: llm-fix [pass 1]", findings:)

    assert_equal "fix_loop: llm-fix [pass 1]\n\nNO_PUTS lib/ok.rb:3\nLONG_LINE lib/ok.rb:9", git.commits.first.first
  end

  def test_nothing_is_committed_without_a_baseline
    write_file("lib/ok.rb", "OK = 1\n")
    git = FakeGit.new(["lib/ok.rb"], ["lib/ok.rb"])
    run_committer(git, FakeBus.new, "fix: ok", baseline: false)
    assert_empty git.commits
  end
end
