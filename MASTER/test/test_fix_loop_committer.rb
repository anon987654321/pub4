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
    attr_reader :commits, :pushes
    attr_writer :ahead

    def initialize(before, after)
      @answers = [before, after]
      @commits = []
      @pushes = 0
      @ahead = 0
    end

    def push = @pushes += 1
    def ahead_behind = [@ahead, 3]

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
    commit_event = bus.events.find { |event, _| event == "ops:commit" }
    assert_equal ["lib/ok.rb"], commit_event.last[:paths]
    assert_equal [], commit_event.last[:findings]
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

  # An explicit fix owns its target: a change already sitting in a target
  # file is committed with the fix, and a dirty path outside it is not.
  def test_owned_paths_commit_prior_changes_inside_the_target_only
    write_file("lib/ok.rb", "OK = 1\n")
    git = FakeGit.new(["lib/ok.rb", "lib/theirs.rb"], ["lib/ok.rb", "lib/theirs.rb"])
    committer = Master::Fix::FixLoop::Committer.new(git:, bus: FakeBus.new, root: @dir)
    committer.baseline!
    committer.commit_if_dirty("fix: ok", owned_paths: [File.join(@dir, "lib/ok.rb")])

    assert_equal [["fix: ok", ["lib/ok.rb"]]], git.commits
    assert_equal 1, git.pushes
  end

  # Behind is the remote moving on; only a commit still ahead means the push
  # missed, and a delivery that missed stops the loop.
  def test_a_push_that_left_the_commit_behind_raises
    write_file("lib/ok.rb", "OK = 1\n")
    git = FakeGit.new([], ["lib/ok.rb"])
    git.ahead = 1
    bus = FakeBus.new

    assert_raises(RuntimeError) { run_committer(git, bus, "fix: ok") }
    assert(bus.events.any? { |event, _| event == "fix_loop:commit_error" })
    refute(bus.events.any? { |event, _| event == "ops:commit" })
  end

  # A lint that did not pass blocks the commit. Io::Exec answers a timed-out
  # rubocop with this same failed status; its own tests pin the timeout.
  def test_a_failed_lint_blocks_the_commit
    write_file("Gemfile", "source 'https://rubygems.org'\n")
    write_file("lib/ok.rb", "OK = 1\n")
    git = FakeGit.new([], ["lib/ok.rb"])
    bus = FakeBus.new
    failed = Struct.new(:success?).new(false)

    Master::Io::Exec.stub(:capture3, ["", "", failed]) { run_committer(git, bus, "fix: ok") }

    assert_empty git.commits
    assert blocked?(bus)
  end

  class BrokenBaselineGit < FakeGit
    def changed_paths
      raise "git status unavailable"
    end
  end

  def test_baseline_failure_blocks_the_transaction
    git = BrokenBaselineGit.new([], [])
    committer = Master::Fix::FixLoop::Committer.new(git:, bus: FakeBus.new, root: @dir)

    error = assert_raises(RuntimeError) { committer.baseline! }

    assert_match(/cannot establish fix transaction baseline: .*git status unavailable/, error.message)
  end

  def test_lint_command_exception_blocks_the_commit
    write_file("Gemfile", "source 'https://rubygems.org'\n")
    write_file("lib/ok.rb", "OK = 1\n")
    git = FakeGit.new([], ["lib/ok.rb"])
    bus = FakeBus.new

    Master::Io::Exec.stub(:capture3, ->(*) { raise "rubocop unavailable" }) do
      run_committer(git, bus, "fix: ok")
    end

    assert_empty git.commits
    assert blocked?(bus)
  end

  def test_nothing_is_committed_without_a_baseline
    write_file("lib/ok.rb", "OK = 1\n")
    git = FakeGit.new(["lib/ok.rb"], ["lib/ok.rb"])
    run_committer(git, FakeBus.new, "fix: ok", baseline: false)
    assert_empty git.commits
  end
end
