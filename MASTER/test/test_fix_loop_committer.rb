# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"

# Regression guard: the fix-loop committer must never commit a tree where an
# autofix left Ruby unparseable (the corruption that motivated this guard).
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

  class FakeGit
    attr_reader :commits

    def initialize(lines)
      @lines = lines
      @commits = []
    end

    def dirty?(_path = ".")
      !@lines.empty?
    end

    def status_lines(_path = nil)
      @lines
    end

    def add_all; end

    def commit(message)
      @commits << message
    end
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

  def run_committer(git, bus, message)
    committer = Master::Fix::FixLoop::Committer.new(git: git, bus: bus, root: @dir)
    committer.commit_if_dirty(message)
  end

  def blocked?(bus)
    bus.events.any? { |event, _payload| event == "fix_loop:commit_blocked" }
  end

  def test_commits_when_changed_ruby_parses
    write_file("lib/ok.rb", "FOO = {\n  a: 1,\n}.freeze\n")
    git = FakeGit.new([" M lib/ok.rb"])
    bus = FakeBus.new
    run_committer(git, bus, "fix: ok")
    assert_equal ["fix: ok"], git.commits
    refute blocked?(bus)
  end

  def test_blocks_commit_on_freeze_corruption
    write_file("lib/bad.rb", "FOO = {.freeze\n  a: 1,\n}.freeze\n")
    git = FakeGit.new([" M lib/bad.rb"])
    bus = FakeBus.new
    run_committer(git, bus, "fix: bad")
    assert_empty git.commits
    assert blocked?(bus)
  end

  def test_blocks_commit_on_missing_end
    write_file("lib/bad2.rb", "def m\n  if x\n  end\n")
    git = FakeGit.new([" M lib/bad2.rb"])
    bus = FakeBus.new
    run_committer(git, bus, "fix: bad2")
    assert_empty git.commits
    assert blocked?(bus)
  end

  def test_ignores_non_ruby_changes
    write_file("README.md", "# hi\n")
    git = FakeGit.new([" M README.md"])
    bus = FakeBus.new
    run_committer(git, bus, "docs: update")
    assert_equal ["docs: update"], git.commits
    refute blocked?(bus)
  end
end
