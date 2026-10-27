# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "stringio"
require "tmpdir"
require_relative "../lib/operator/replay_push"

# A bare origin and two clones of it: `ours` is the shared checkout, `theirs`
# the other session that pushed first.
module ReplayPushRepos

  def push
    out = StringIO.new
    ok = Operator::ReplayPush.new(root: @ours, out:).run
    [ok, out.string]
  end

  def clone_origin(name)
    path = File.join(@dir, name)
    git(@dir, "clone", "-q", @origin, path)
    git(path, "config", "user.name", "Tester")
    git(path, "config", "user.email", "tester@example.invalid")
    git(path, "config", "core.hooksPath", "/dev/null")
    path
  end

  # Writes one file and commits it; returns the new HEAD.
  def commit_file(repo, path:, text:, subject:)
    File.write(File.join(repo, path), text)
    git(repo, "add", path)
    git(repo, "commit", "-q", "-m", subject)
    git(repo, "rev-parse", "HEAD").strip
  end

  def theirs_pushed(path:, text:, subject:)
    commit_file(@theirs, path:, text:, subject:)
    git(@theirs, "push", "-q", "origin", "main")
  end

  def remote_main = git(@ours, "ls-remote", "origin", "refs/heads/main").split.first

  def local_head = git(@ours, "rev-parse", "HEAD").strip

  def git(dir, *args)
    env = { "GIT_CONFIG_NOSYSTEM" => "1", "HOME" => @dir }
    out, status = Open3.capture2e(env, "git", *args, chdir: dir)
    raise "git #{args.join(" ")} failed in #{dir}: #{out}" unless status.success?

    out
  end
end

# Each case asserts what reached origin and what was left of the checkout,
# including a file nobody committed.
class TestOperatorReplayPush < Minitest::Test
  include ReplayPushRepos

  def setup
    @dir = Dir.mktmpdir("replay-push-")
    @origin = File.join(@dir, "origin.git")
    git(@dir, "init", "-q", "--bare", "-b", "main", @origin)
    @ours = clone_origin("ours")
    commit_file(@ours, path: "shared.txt", text: "one\ntwo\nthree\n", subject: "Seed")
    git(@ours, "push", "-q", "origin", "main")
    @theirs = clone_origin("theirs")
  end

  def teardown = FileUtils.rm_rf(@dir)

  def test_replays_onto_a_moved_origin_and_keeps_the_dirty_tree
    theirs_pushed(path: "theirs.txt", text: "theirs\n", subject: "Their change")
    old = commit_file(@ours, path: "ours.txt", text: "ours\n", subject: "Our change")
    File.write(File.join(@ours, "shared.txt"), "uncommitted\n")

    ok, out = push

    assert ok, out
    assert_equal remote_main, local_head
    assert_equal ["Our change", "Their change", "Seed"], git(@ours, "log", "--format=%s", "HEAD").lines(chomp: true)
    assert_match(/#{old[0, 9]} -> #{local_head[0, 9]} Our change/, out)
    assert_equal "uncommitted\n", File.read(File.join(@ours, "shared.txt"))
  end

  def test_the_replayed_commit_keeps_its_author
    theirs_pushed(path: "theirs.txt", text: "theirs\n", subject: "Their change")
    File.write(File.join(@ours, "ours.txt"), "ours\n")
    git(@ours, "add", "ours.txt")
    git(@ours, "commit", "-q", "--author=Author <author@example.invalid>", "-m", "Authored")

    ok, out = push

    assert ok, out
    assert_equal "Author <author@example.invalid> by Tester", git(@ours, "log", "-1", "--format=%an <%ae> by %cn").strip
  end

  def test_a_conflict_refuses_before_anything_is_pushed_or_reset
    theirs_pushed(path: "shared.txt", text: "one\ntheirs\nthree\n", subject: "Theirs on line two")
    before = remote_main
    local = commit_file(@ours, path: "shared.txt", text: "one\nours\nthree\n", subject: "Ours on line two")

    ok, out = push

    refute ok
    assert_match(%r{conflicts with origin/main}, out)
    assert_equal [before, local], [remote_main, local_head]
  end

  def test_a_rejected_push_leaves_the_checkout_where_it_was
    theirs_pushed(path: "theirs.txt", text: "theirs\n", subject: "Their change")
    hook = File.join(@origin, "hooks", "pre-receive")
    File.write(hook, "#!/bin/sh\nexit 1\n")
    File.chmod(0o755, hook)
    local = commit_file(@ours, path: "ours.txt", text: "ours\n", subject: "Our change")

    ok, out = push

    refute ok
    assert_match(/git push failed, nothing reset/, out)
    assert_equal local, local_head
  end

  def test_a_change_origin_already_has_is_dropped
    theirs_pushed(path: "same.txt", text: "same\n", subject: "Theirs")
    commit_file(@ours, path: "same.txt", text: "same\n", subject: "Ours, identical")

    ok, out = push

    assert ok, out
    assert_match(/already on origin, dropped: Ours, identical/, out)
    assert_equal remote_main, local_head
  end

  def test_an_unmoved_origin_takes_the_commits_with_their_hashes
    local = commit_file(@ours, path: "ours.txt", text: "ours\n", subject: "Our change")

    ok, out = push

    assert ok, out
    assert_equal local, remote_main
    assert_match(/#{local[0, 9]} -> #{local[0, 9]}/, out)
  end

  def test_nothing_unpublished_pushes_nothing
    ok, out = push

    assert ok, out
    assert_match(/nothing on main that origin lacks/, out)
  end

  def test_a_merge_commit_is_refused
    git(@ours, "checkout", "-q", "-b", "side")
    commit_file(@ours, path: "side.txt", text: "side\n", subject: "Side")
    git(@ours, "checkout", "-q", "main")
    commit_file(@ours, path: "main.txt", text: "main\n", subject: "Main")
    git(@ours, "merge", "-q", "--no-edit", "side")

    ok, out = push

    refute ok
    assert_match(/merge commit/, out)
  end
end
