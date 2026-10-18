# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "open3"
require "json"
require "rbconfig"

class TestFixWorktreeSession < Minitest::Test
  def test_disk_preflight_uses_interrupt_safe_subprocess_capture
    with_repo(worker: "#!/usr/bin/env ruby\\nexit 3\\n") do |root|
      session = Master::Fix::WorktreeSession.new(root:)
      status = Struct.new(:success?).new(true)
      calls = []
      output = "Filesystem 1024-blocks Used Available Capacity Mounted on\\n/dev/disk 100000 1000 99000 1% /\\n"

      Master::Io::Exec.stub(:capture2e, lambda { |*args, **_opts|
        calls << args
        [output, status]
      }) do
        assert_operator session.send(:disk_free_gb), :>, 0
      end

      assert_equal 2, calls.size
      assert calls.all? { |args| args.first == "df" }
    end
  end

  def test_disk_preflight_refuses_worktree_before_writing
    with_repo(worker: "#!/usr/bin/env ruby\nexit 3\n") do |root|
      session = Master::Fix::WorktreeSession.new(root:)
      session.define_singleton_method(:disk_free_gb) { 1.25 }

      result = session.run(command: "/fix test")

      refute result.ok
      assert_match(/disk preflight: 1.25 GB free, 2.00 GB required/, result.summary)
      assert_nil result.worktree
      assert_equal "base\n", git_output(root, "show", "origin/main:README")
      refute_match(/checkout/, git_output(root, "worktree", "list"))
    end
  end

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
        puts "review0: complete"
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

  def test_remote_branch_state_distinguishes_absent_and_present_refs
    with_repo(worker: "#!/usr/bin/env ruby\nexit 0\n") do |root|
      session = Master::Fix::WorktreeSession.new(root:)

      assert_equal :absent, session.send(:remote_branch_state, "missing-branch")
      git(root, "push", "origin", "HEAD:refs/heads/temporary")
      assert_equal :present, session.send(:remote_branch_state, "temporary")
    end
  end

  def test_remote_branch_cleanup_failure_is_reported_after_delivery
    worker = <<~'RUBY'
      #!/usr/bin/env ruby
      File.write("README", "after\n")
      system("git", "add", "README")
      puts "review0: complete"
      exit(system("git", "commit", "-m", "worker fix"))
    RUBY

    with_repo(worker:, deny_deletes: true) do |root|
      result = Master::Fix::WorktreeSession.new(root:).run(command: "/fix test", proof_trees: ["MASTER"])

      assert result.ok
      assert_match(/published/, result.summary)
      assert_includes result.summary, "remote branch cleanup failed, retained origin/#{result.branch}"
      refute File.exist?(result.worktree)
      assert_equal "after\n", git_output(root, "show", "origin/main:README")
      refute_empty git_output(root, "ls-remote", "--heads", "origin", result.branch)
    end
  end

  def test_streamed_worker_output_redacts_credentials_but_retains_terminal_evidence
    with_repo(worker: "#!/usr/bin/env ruby\nexit 0\n") do |root|
      code = <<~'RUBY'
        puts "remote https://operator:password-value@example.invalid/repo.git?token=query-token"
        puts "review0: complete"
      RUBY

      status = nil
      lines = nil
      out, err = capture_io do
        session = Master::Fix::WorktreeSession.new(root:)
        status, lines = session.send(:run_stream, ENV.to_h, RbConfig.ruby, "-e", code, chdir: root, timeout_s: 5)
      end

      assert status, err + out
      raw_line = "remote https://operator:password-value@example.invalid/repo.git?token=query-token"
      assert_includes lines, raw_line, "state detection retains the child's original evidence"
      assert_includes out + err, "remote https://[redacted]@example.invalid/repo.git?token=[redacted]"
      refute_includes out + err, "password-value"
      refute_includes out + err, "query-token"
      assert_includes out + err, "review0: complete"
    end
  end

  def test_error_diagnostics_redact_credentials_and_bound_output
    with_repo(worker: "#!/usr/bin/env ruby\nexit 0\n") do |root|
      session = Master::Fix::WorktreeSession.new(root:)
      stripe_key = "sk_live_#{'A' * 24}"
      replicate_key = "r8_#{'B' * 24}"
      error = RuntimeError.new(
        "remote https://operator:password-value@example.invalid/repo.git?token=query-token&client_secret=url-secret " \
        "Authorization: Bearer bearer-value Authorization: raw-auth-secret " \
        "REPLICATE_API_TOKEN=replicate-secret-value #{stripe_key} #{replicate_key} ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ123456"
      )

      message = session.send(:safe_error_message, error)

      assert_includes message, "https://[redacted]@example.invalid/repo.git?token=[redacted]&client_secret=[redacted]"
      assert_includes message, "Authorization: Bearer [redacted]"
      assert_includes message, "Authorization: [redacted]"
      refute_includes message, "password-value"
      refute_includes message, "query-token"
      refute_includes message, "bearer-value"
      refute_includes message, "ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ123456"
      refute_includes message, "raw-auth-secret"
      refute_includes message, "replicate-secret-value"
      refute_includes message, "url-secret"
      refute_includes message, stripe_key
      refute_includes message, replicate_key
      assert_operator message.length, :<=, 500
      assert_equal 500, session.send(:safe_error_message, RuntimeError.new("x" * 800)).length
    end
  end

  def test_final_publication_failure_is_delivery_failed_and_preserves_recovery
    worker = <<~'RUBY'
      #!/usr/bin/env ruby
      File.write("README", "after\n")
      system("git", "add", "README")
      puts "review0: complete"
      exit(system("git", "commit", "-m", "worker fix") ? 0 : 1)
    RUBY

    with_repo(worker:) do |root|
      session = Master::Fix::WorktreeSession.new(root:)
      session.define_singleton_method(:publish!) do |worktree:, branch:, head:, base:|
        raise IOError,
              "private push URL https://user:secret@example.test/repo.git; PR https://github.com/anon987654321/pub4/pull/99"
      end

      result = nil
      out, err = capture_io do
        result = session.run(command: "/fix test", proof_trees: ["MASTER"])
      end

      refute result.ok, err + out
      assert_equal :delivery_failed, result.category
      assert_match(/\ADELIVERY_FAILED: final publication did not complete cleanly \(IOError\); PR https:\/\/github\.com\/anon987654321\/pub4\/pull\/99/, result.summary)
      refute_includes result.summary, "private push URL"
      refute_includes result.summary, "user:secret"
      assert File.directory?(result.worktree), "unpublished work must remain available for recovery"
      assert_equal "base\n", git_output(root, "show", "origin/main:README")
      refute_empty git_output(root, "ls-remote", "--heads", "origin", result.branch)
    ensure
      if result&.worktree && File.directory?(result.worktree)
        git(root, "worktree", "remove", "--force", result.worktree)
      end
      if result&.branch
        git(root, "branch", "-D", result.branch)
        git(root, "push", "origin", "--delete", result.branch, out: File::NULL, err: File::NULL)
      end
      FileUtils.rm_rf(File.dirname(result.worktree)) if result&.worktree
    end
  end

  def test_worker_terminal_categories_preserve_human_decisions_and_recovery_states
    session = Master::Fix::WorktreeSession.allocate
    states = {
      "fix0: HUMAN_DECISION: approval required" => :human_decision,
      "fix0: BLOCKED: outside authority" => :policy,
      "fix0: INCONCLUSIVE: semantic evidence unavailable" => :inconclusive,
      "fix0: PLATEAU: no convergence" => :plateau,
      "fix0: RELOADING: main changed" => :reloading,
      "fix0: DELIVERY_FAILED: push refused" => :delivery_failed,
      "fix0: TIMEOUT: budget expired" => :timeout,
      "fix0: FAILED: unexpected outcome" => :failed,
      "fix0: complete with open findings" => :plateau,
    }

    states.each do |line, expected|
      assert_equal expected, session.send(:worker_terminal_category, line), line
      assert_equal line, session.send(:worker_terminal_failure, [line]), line
    end
  end

  def test_gate_baseline_cache_survives_disposable_worktree
    worker = <<~'RUBY'
      #!/usr/bin/env ruby
      require "json"
      cache = File.join(Dir.pwd, "MASTER", ".master", "gate_baseline.json")
      abort "baseline cache not carried into worktree" unless JSON.parse(File.read(cache)).fetch("key") == "parent-key"
      File.write(cache, JSON.generate("key" => "child-key", "snapshot" => {}))
      File.write("README", "after\n")
      system("git", "add", "README")
      puts "review0: complete"
      exit(system("git", "commit", "-m", "worker fix") ? 0 : 1)
    RUBY

    with_repo(worker:) do |root|
      exclude = File.join(root, ".git", "info", "exclude")
      File.open(exclude, "a") { |io| io.puts("MASTER/.master/") }
      cache = File.join(root, "MASTER", ".master", "gate_baseline.json")
      FileUtils.mkdir_p(File.dirname(cache))
      File.write(cache, JSON.generate("key" => "parent-key", "snapshot" => {}))

      result = Master::Fix::WorktreeSession.new(root:).run(command: "/fix test", proof_trees: ["MASTER"])

      assert result.ok, result.summary
      assert_equal "child-key", JSON.parse(File.read(cache)).fetch("key"),
                   "the child's newly measured baseline was discarded with the worktree"
      assert_equal "base\n", File.read(File.join(root, "README"))
      assert_equal "after\n", git_output(root, "show", "origin/main:README")
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
        puts "review0: complete"
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
        Master::Io::GitHubOperations::Result.new(true, "merged", 99, "https://github.com/anon987654321/pub4/pull/99", "a" * 40)
      end

      result = Master::Fix::WorktreeSession.new(root:, github:).run(command: "/fix test", proof_trees: ["MASTER"])

      assert result.ok
      assert_equal 1, calls.size
      assert_equal "main", calls.first[:base]
      assert_equal result.head, calls.first[:expected_head]
      assert_includes result.summary, "as #{"a" * 12} to origin/main"
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
    puts "review0: complete"
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
    puts "review0: complete"
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

def test_zero_exit_without_a_completion_report_is_not_success
    with_repo(worker: "#!/usr/bin/env ruby\\nexit 0\\n") do |root|
      result = Master::Fix::WorktreeSession.new(root:).run(command: "/fix test")

      refute result.ok
      assert_match(/without an explicit completion report/, result.summary)
      refute File.exist?(result.worktree)
    end
  end

  def test_zero_exit_with_open_findings_is_not_success
    with_repo(worker: "#!/usr/bin/env ruby\nputs \"review0: complete with open findings\"\nexit 0\n") do |root|
      result = nil
      out, err = capture_io { result = Master::Fix::WorktreeSession.new(root:).run(command: "/fix test") }

      refute result.ok, err + out
      assert_match(/incomplete terminal state: review0: complete with open findings/, result.summary)
      refute_match(/clean, no changes to publish/, result.summary)
      refute File.exist?(result.worktree)
      assert_empty git_output(root, "branch", "--list", result.branch)
    end
  end

  def test_zero_exit_with_incomplete_terminal_report_is_not_success
    with_repo(worker: "#!/usr/bin/env ruby\nputs \"review0: incomplete, validation unavailable\"\nexit 0\n") do |root|
      result = nil
      out, err = capture_io { result = Master::Fix::WorktreeSession.new(root:).run(command: "/fix test") }

      refute result.ok, err + out
      assert_match(/incomplete terminal state/, result.summary)
      refute_match(/clean, no changes to publish/, result.summary)
      refute File.exist?(result.worktree)
      assert_empty git_output(root, "branch", "--list", result.branch)
    end
  end

  def test_interrupt_during_final_proof_preserves_committed_work_and_recovery_instructions
    worker = <<~RUBY
      #!/usr/bin/env ruby
      File.write("README", "after\n")
      system("git", "add", "README")
      puts "review0: complete"
      exit(system("git", "commit", "-m", "worker fix"))
    RUBY
    with_repo(worker:) do |root|
      session = Master::Fix::WorktreeSession.new(root:)
      session.define_singleton_method(:run_proof) { |worktree, proof_trees:| raise Interrupt, "simulated operator cancellation" }

      result = nil
      out, err = capture_io { result = session.run(command: "/fix test", proof_trees: ["MASTER"]) }

      refute result.ok, err + out
      assert_match(/cancelled by operator/, result.summary)
      assert File.directory?(result.worktree), "partial work must be retained for recovery"
      assert_includes err + out, "inspect: git -C #{result.worktree} status --short"
      assert_equal "after\n", git_output(root, "show", "#{result.branch}:README")
    ensure
      if result&.worktree && File.directory?(result.worktree)
        git(root, "worktree", "remove", "--force", result.worktree)
        git(root, "branch", "-D", result.branch)
        FileUtils.rm_rf(File.dirname(result.worktree))
      end
    end
  end

  def test_worker_timeout_terminates_the_group_and_finishes_with_a_terminal_result
    previous = ENV["MASTER_FIX_WORKTREE_TIMEOUT_S"]
    ENV["MASTER_FIX_WORKTREE_TIMEOUT_S"] = "1"
    with_repo(worker: "#!/usr/bin/env ruby\nfork { sleep 30 }\nsleep 30\n") do |root|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = nil
      out, err = capture_io { result = Master::Fix::WorktreeSession.new(root:).run(command: "/fix test") }
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      refute result.ok, err + out
      assert_match(/timeout after 1s/, result.summary)
      assert_operator elapsed, :<, 8, "timed out child or descendant kept the run alive"
      refute File.exist?(result.worktree)
      assert_empty git_output(root, "branch", "--list", result.branch)
    end
  ensure
    previous.nil? ? ENV.delete("MASTER_FIX_WORKTREE_TIMEOUT_S") : ENV["MASTER_FIX_WORKTREE_TIMEOUT_S"] = previous
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
    assert_includes text, "discard: git -C #{root} worktree remove --force #{result.worktree}"
    assert_includes text, "branch -D #{result.branch}"
  ensure
    if result&.worktree && File.directory?(result.worktree)
      git(root, "worktree", "remove", "--force", result.worktree)
      FileUtils.rm_rf(File.dirname(result.worktree))
    end
  end
end

private

def with_repo(worker:, deny_deletes: false)
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
    git(remote, "config", "receive.denyDeletes", "true", out: File::NULL, err: File::NULL) if deny_deletes
    yield root
  end
end

  def write_worker(root)
    FileUtils.mkdir_p(File.join(root, "MASTER", "bin"))
    File.write(File.join(root, "MASTER", "bin", "master"), <<~RUBY)
      #!/usr/bin/env ruby
      File.write(File.join(Dir.pwd, "README"), "after\n")
      system("git", "add", "README")
      puts "review0: complete"
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
