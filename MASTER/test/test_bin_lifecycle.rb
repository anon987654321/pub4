# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "rbconfig"
require "yaml"

# The session scripts in bin/, run as processes. Each one that writes resolves
# its paths from its own location, so it runs from a copy inside a scratch tree
# and the checkout is never touched.
class TestBinLifecycle < Minitest::Test
  BIN = File.join(Master::ROOT, "bin")

  def run_script(path, *args, env: {}, chdir: Master::ROOT)
    Open3.capture2e(env, RbConfig.ruby, path, *args, chdir:)
  end

  # A copy at <scratch>/MASTER/bin/<name>, so ROOT and REPO land in the scratch.
  def staged(scratch, name)
    dest = File.join(scratch, "MASTER", "bin", name)
    FileUtils.mkdir_p(File.dirname(dest))
    FileUtils.cp(File.join(BIN, name), dest)
    dest
  end

  def git(dir, *args)
    out, status = Open3.capture2e("git", "-C", dir, *args)
    assert status.success?, out
  end

  # The scripted run must be refused its `done`: three commands that only label
  # themselves as evidence prove nothing, and a fold that accepts them grades its
  # own paper.
  def test_master_core_holds_done_without_evidence
    Dir.mktmpdir do |scratch|
      out, status = run_script(File.join(BIN, "master-core"), "--root", scratch, "noop")

      assert status.success?, out
      assert_includes out, "held — done refused without passing evidence"
    end
  end

  def test_master_core_without_a_goal_prints_usage
    out, status = run_script(File.join(BIN, "master-core"))

    assert_equal 64, status.exitstatus
    assert_includes out, "usage: master-core"
  end

  def test_cleanup_refuses_a_dirty_tree_and_only_reports_on_a_clean_one
    Dir.mktmpdir do |scratch|
      script = staged(scratch, "cleanup")
      git(scratch, "init", "-q")
      git(scratch, "config", "user.email", "test@example.invalid")
      git(scratch, "config", "user.name", "test")
      git(scratch, "add", ".")
      git(scratch, "commit", "-q", "-m", "base")
      File.write(File.join(scratch, "test_leftover.jpg"), "x")

      dirty, dirty_status = run_script(script, chdir: scratch)
      refute dirty_status.success?
      assert_includes dirty, "working tree dirty"

      File.delete(File.join(scratch, "test_leftover.jpg"))
      clean, clean_status = run_script(script, chdir: scratch)
      assert clean_status.success?, clean
      assert_includes clean, "dry-run only"
      assert_path_exists File.join(scratch, "MASTER", "reports", "cleanup")
    end
  end
end
