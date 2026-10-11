# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "tmpdir"

# Two merges left dangling requires (core/capabilities) that no unit test saw.
# Landing and finishing a worktree now boot the runtime after the rebase and
# refuse to publish when it does not.
class TestWorktreeBootGuard < Minitest::Test
  SCRIPT = File.expand_path("../../OPENBSD/dev/agent_worktree.sh", __dir__)
  OPERATOR = File.expand_path("../bin/operator", __dir__)

  def git(dir, *args)
    out, status = Open3.capture2e("git", "-C", dir, *args)
    raise "git #{args.join(" ")}: #{out}" unless status.success?

    out
  end

  # A clone of a bare origin, on agent/x, with a MASTER whose smoke exits as told.
  def with_repo(smoke_exit)
    Dir.mktmpdir do |dir|
      origin = File.join(dir, "origin.git")
      work = File.join(dir, "work")
      git(dir, "init", "-q", "--bare", "--initial-branch=main", origin)
      git(dir, "clone", "-q", origin, work)
      git(work, "config", "user.email", "t@example.invalid")
      git(work, "config", "user.name", "T")
      FileUtils.mkdir_p(File.join(work, "MASTER", "bin"))
      FileUtils.mkdir_p(File.join(work, "MASTER", "tools"))
      File.write(File.join(work, "MASTER", "bin", "ruby"), "#!/bin/sh\nexec #{RbConfig.ruby} \"$@\"\n")
      FileUtils.chmod(0o755, File.join(work, "MASTER", "bin", "ruby"))
      File.write(File.join(work, "MASTER", "tools", "boot_smoke.rb"), "exit #{smoke_exit}\n")
      git(work, "add", "-A")
      git(work, "commit", "-qm", "base")
      git(work, "push", "-q", "origin", "HEAD:main")
      git(work, "checkout", "-q", "-b", "agent/x")
      yield work, origin
    end
  end

  def finish(work)
    Open3.capture2e("sh", SCRIPT, "finish", chdir: work)
  end

  def test_finish_refuses_to_push_when_the_runtime_does_not_boot
    with_repo(1) do |work, origin|
      out, status = finish(work)

      refute status.success?, out
      assert_match(/does not boot/, out)
      assert_empty git(origin, "branch", "--list", "agent/x").strip
    end
  end

  def test_finish_pushes_the_branch_when_the_runtime_boots
    with_repo(0) do |work, origin|
      out, status = finish(work)

      assert status.success?, out
      refute_empty git(origin, "branch", "--list", "agent/x").strip
    end
  end

  # land is a Ruby script that cannot be loaded without running it; the order is
  # the contract, so the smoke must sit between the second measure and the push.
  def test_land_boots_the_runtime_after_the_rebase_and_before_the_push
    land = File.read(OPERATOR)[/^when "land"$.*?^when "visual"$/m]
    refute_nil land

    rebase = land.index('"rebase", "-q", "origin/main"')
    smoke = land.index("boot_smoke.rb")
    push = land.index('"push", "origin", "HEAD:main"')
    assert rebase && smoke && push && rebase < smoke && smoke < push
    assert_match(/does not boot after the rebase; nothing pushed/, land)
  end
end
