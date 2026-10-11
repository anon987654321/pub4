# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "open3"

class TestFixWorktreeSession < Minitest::Test
  def test_successful_worker_is_published_and_worktree_is_removed
    Dir.mktmpdir("master-worktree-test-") do |dir|
      remote = File.join(dir, "remote.git")
      root = File.join(dir, "pub4")
      system("git", "init", "--bare", remote)
      system("git", "clone", remote, root)
      git(root, "config", "user.name", "MASTER test")
      git(root, "config", "user.email", "master-test@example.invalid")

      FileUtils.mkdir_p(File.join(root, "MASTER", "bin"))
      File.write(File.join(root, "README"), "before\n")
      File.write(File.join(root, "MASTER", "bin", "master"), <<~RUBY)
        #!/usr/bin/env ruby
        path = File.join(Dir.pwd, "README")
        File.write(path, "after\n")
        system("git", "add", "README")
        exit(system("git", "commit", "-m", "worker fix"))
      RUBY
      File.write(File.join(root, "MASTER", "bin", "operator"), "#!/usr/bin/env ruby\nexit 0\n")
      FileUtils.chmod(0o755, File.join(root, "MASTER", "bin", "master"))
      FileUtils.chmod(0o755, File.join(root, "MASTER", "bin", "operator"))

      git(root, "add", ".")
      git(root, "commit", "-m", "initial")
      git(root, "branch", "-M", "main")
      git(root, "push", "-u", "origin", "main")

      File.write(File.join(root, "foreign.txt"), "keep me\n")

      session = Master::Fix::WorktreeSession.new(root:)
      result = session.run(
        command: "/fix test",
        foreign_paths: ["foreign.txt"],
        proof_trees: ["MASTER"],
      )

      assert result.ok
      assert_match(/published/, result.summary)
      assert_equal "before\n", File.read(File.join(root, "README"))
      assert_equal "", git_output(root, "show", "origin/main:README") == "after\n" ? "" : "wrong remote content"
      refute File.exist?(result.worktree)
      assert_empty git_output(root, "ls-remote", "--heads", "origin", result.branch)
      assert_equal ["foreign.txt"], git_output(root, "status", "--porcelain=v1").lines.map { |line| line[3..].to_s.strip }
    end
  end

  def test_auto_merge_uses_fetched_main_when_local_main_is_behind
    Dir.mktmpdir("master-worktree-test-") do |dir|
      remote = File.join(dir, "remote.git")
      root = File.join(dir, "pub4")
      system("git", "init", "--bare", remote)
      system("git", "clone", remote, root)
      git(root, "config", "user.name", "MASTER test")
      git(root, "config", "user.email", "master-test@example.invalid")
      File.write(File.join(root, "README"), "base\n")
      write_worker(root)
      git(root, "add", ".")
      git(root, "commit", "-m", "initial")
      git(root, "branch", "-M", "main")
      git(root, "push", "-u", "origin", "main")
      remote_root = File.join(dir, "remote-update")
      system("git", "clone", remote, remote_root)
      git(remote_root, "config", "user.name", "MASTER test")
      git(remote_root, "config", "user.email", "master-test@example.invalid")
      git(remote_root, "commit", "--allow-empty", "-m", "remote update")
      git(remote_root, "push", "origin", "main")
      File.write(File.join(root, "foreign.txt"), "keep me\n")

      result = Master::Fix::WorktreeSession.new(root:).run(command: "/fix test")

      assert result.ok
      assert_match(/published/, result.summary)
      assert_equal "base\n", File.read(File.join(root, "README"))
      assert_equal "keep me\n", File.read(File.join(root, "foreign.txt"))
      assert_equal "after\n", git_output(root, "show", "origin/main:README")
    end
  end

  def test_github_remote_uses_pr_delivery_without_pushing_main
    Dir.mktmpdir("master-github-worktree-test-") do |dir|
      remote = File.join(dir, "remote.git")
      root = File.join(dir, "pub4")
      system("git", "init", "--bare", remote)
      system("git", "clone", remote, root)
      git(root, "config", "user.name", "MASTER test")
      git(root, "config", "user.email", "master-test@example.invalid")
      File.write(File.join(root, "README"), "base\n")
      FileUtils.mkdir_p(File.join(root, "MASTER", "bin"))
      File.write(File.join(root, "MASTER", "bin", "master"), <<~RUBY)
        #!/usr/bin/env ruby
        File.write(File.join(Dir.pwd, "README"), "after\n")
        system("git", "add", "README")
        exit(system("git", "commit", "-m", "worker fix"))
      RUBY
      FileUtils.chmod(0o755, File.join(root, "MASTER", "bin", "master"))
      File.write(File.join(root, "MASTER", "bin", "operator"), "#!/usr/bin/env ruby\nexit 0\n")
      FileUtils.chmod(0o755, File.join(root, "MASTER", "bin", "operator"))
      git(root, "add", ".")
      git(root, "commit", "-m", "initial")
      git(root, "branch", "-M", "main")
      git(root, "push", "-u", "origin", "main")

      github = Object.new
      calls = []
      github.define_singleton_method(:github_remote?) { true }
      github.define_singleton_method(:publish_and_merge!) do |**kwargs|
        calls << kwargs
        Master::Io::GitHubOperations::Result.new(true, "merged", 99, "https://github.com/anon987654321/pub4/pull/99", "merged-sha")
      end

      result = Master::Fix::WorktreeSession.new(root:, github:).run(command: "/fix test", proof_trees: ["MASTER"])

      assert result.ok
      assert_equal 1, calls.size
      assert_equal "main", calls.first[:base]
      assert_equal result.head, calls.first[:expected_head]
      assert_equal "base\n", git_output(root, "show", "origin/main:README")
      refute File.exist?(result.worktree)
    end
  end

  def test_auto_merge_refuses_preexisting_local_commits
    Dir.mktmpdir("master-worktree-test-") do |dir|
      remote = File.join(dir, "remote.git")
      root = File.join(dir, "pub4")
      system("git", "init", "--bare", remote)
      system("git", "clone", remote, root)
      git(root, "config", "user.name", "MASTER test")
      git(root, "config", "user.email", "master-test@example.invalid")
      File.write(File.join(root, "README"), "base\n")
      git(root, "add", "README")
      git(root, "commit", "-m", "initial")
      git(root, "branch", "-M", "main")
      git(root, "push", "-u", "origin", "main")
      File.write(File.join(root, "README"), "local\n")
      git(root, "commit", "-am", "local work")

      result = Master::Fix::WorktreeSession.new(root:).run(command: "/fix test")

      refute result.ok
      assert_match(/local main has unpushed or divergent commits/, result.summary)
      assert_equal "base\n", git_output(root, "show", "origin/main:README")
      assert_equal "local\n", File.read(File.join(root, "README"))
    end
  end

def test_uncommitted_tracked_edits_are_reported_and_left_out_by_default
  with_repo(worker: <<~RUBY) do |root|
    #!/usr/bin/env ruby
    File.write("README", File.read("MASTER/lib/x.rb"))
    system("git", "add", "README")
    exit(system("git", "commit", "-m", "worker fix"))
  RUBY
    File.write(File.join(root, "MASTER", "lib", "x.rb"), "dirty\n")
    File.write(File.join(root, "untracked.txt"), "render\n")

    result = nil
    out, err = capture_io { result = Master::Fix::WorktreeSession.new(root:).run(command: "/fix test", proof_trees: ["MASTER"]) }

    assert result.ok, err + out
    assert_match(/1 uncommitted edit\(s\) in MASTER\/lib\/x\.rb are NOT in this run/, err + out)
    assert_equal "clean\n", git_output(root, "show", "origin/main:README")
  end
end

def test_include_dirty_copies_tracked_edits_without_committing_them
  with_repo(worker: <<~RUBY) do |root|
    #!/usr/bin/env ruby
    File.write("README", File.read("MASTER/lib/x.rb"))
    File.write("untracked_seen.txt", "x") if File.exist?("untracked.txt")
    system("git", "add", "README")
    exit(system("git", "commit", "-m", "worker fix"))
  RUBY
    File.write(File.join(root, "MASTER", "lib", "x.rb"), "dirty\n")
    File.write(File.join(root, "untracked.txt"), "render\n")

    result = nil
    out, err = capture_io do
      result = Master::Fix::WorktreeSession.new(root:).run(command: "/fix test", proof_trees: ["MASTER"], include_dirty: true)
    end

    assert result.ok, err + out
    assert_match(/copied into this run \(--include-dirty\)/, err + out)
    assert_equal "dirty\n", git_output(root, "show", "origin/main:README")
    assert_equal "clean\n", git_output(root, "show", "origin/main:MASTER/lib/x.rb")
    assert_equal "render\n", File.read(File.join(root, "untracked.txt"))
  end
end

def test_failed_worker_that_wrote_nothing_removes_worktree_and_branch
  with_repo(worker: "#!/usr/bin/env ruby\nexit 3\n") do |root|
    result = nil
    out, err = capture_io { result = Master::Fix::WorktreeSession.new(root:).run(command: "/fix test") }

    refute result.ok
    assert_match(/nothing was written/, result.summary, err + out)
    refute File.exist?(result.worktree)
    assert_empty git_output(root, "branch", "--list", result.branch)
    assert_empty git_output(root, "ls-remote", "--heads", "origin", result.branch)
  end
end

def test_failed_worker_with_kept_work_prints_path_branch_and_recovery
  with_repo(worker: "#!/usr/bin/env ruby\nFile.write('half.txt', 'partial')\nexit 3\n") do |root|
    result = nil
    out, err = capture_io { result = Master::Fix::WorktreeSession.new(root:).run(command: "/fix test") }

    refute result.ok
    assert File.directory?(result.worktree)
    text = err + out
    assert_includes text, "retained worktree: #{result.worktree}"
    assert_includes text, "retained branch: #{result.branch}"
    assert_includes text, "inspect: git -C #{result.worktree} status --short"
    assert_includes text, "branch -D #{result.branch}"
  ensure
    if result&.worktree && File.directory?(result.worktree)
      git(root, "worktree", "remove", "--force", result.worktree)
      FileUtils.rm_rf(File.dirname(result.worktree))
    end
  end
end

private

def with_repo(worker:)
  Dir.mktmpdir("master-worktree-test-") do |dir|
    remote = File.join(dir, "remote.git")
    root = File.join(dir, "pub4")
    system("git", "init", "--bare", remote, out: File::NULL, err: File::NULL)
    system("git", "clone", remote, root, out: File::NULL, err: File::NULL)
    git(root, "config", "user.name", "MASTER test")
    git(root, "config", "user.email", "master-test@example.invalid")
    FileUtils.mkdir_p(File.join(root, "MASTER", "bin"))
    FileUtils.mkdir_p(File.join(root, "MASTER", "lib"))
    File.write(File.join(root, "README"), "base\n")
    File.write(File.join(root, "MASTER", "lib", "x.rb"), "clean\n")
    File.write(File.join(root, "MASTER", "bin", "master"), worker)
    File.write(File.join(root, "MASTER", "bin", "operator"), "#!/usr/bin/env ruby\nexit 0\n")
    FileUtils.chmod(0o755, [File.join(root, "MASTER", "bin", "master"), File.join(root, "MASTER", "bin", "operator")])
    git(root, "add", ".")
    git(root, "commit", "-m", "initial", out: File::NULL)
    git(root, "branch", "-M", "main")
    git(root, "push", "-u", "origin", "main", out: File::NULL, err: File::NULL)
    yield root
  end
end

  def write_worker(root)
    FileUtils.mkdir_p(File.join(root, "MASTER", "bin"))
    File.write(File.join(root, "MASTER", "bin", "master"), <<~RUBY)
      #!/usr/bin/env ruby
      File.write(File.join(Dir.pwd, "README"), "after\n")
      system("git", "add", "README")
      exit(system("git", "commit", "-m", "worker fix"))
    RUBY
    File.write(File.join(root, "MASTER", "bin", "operator"), "#!/usr/bin/env ruby\nexit 0\n")
    FileUtils.chmod(0o755, [File.join(root, "MASTER", "bin", "master"), File.join(root, "MASTER", "bin", "operator")])
  end

  def git(root, *args, **opts)
    system("git", "-C", root, *args, **opts)
  end

  def git_output(root, *args)
    Open3.capture2e("git", "-C", root, *args).first
  end
end
