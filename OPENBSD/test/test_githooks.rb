# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"

# The three guards in OPENBSD/dev/githooks are the only thing standing between a
# shared checkout and the accidents CLAUDE.md calls trap one, and until now
# nothing proved they still refuse anything. They are prose about prose: a hook
# that stopped firing would look exactly like a tree in which nobody made the
# mistake, and the mistakes they were written for — a cross-tree `git commit -a`,
# a push carrying four other sessions' commits, a move that half-landed — all
# happened in the week before the hooks existed, so there is no shortage of
# evidence about what silence costs.
#
# These run the real hooks through real git, in a throwaway repository, because
# a hook is only installed behaviour: unit-testing its logic would not have
# caught a missing chmod, a bad shebang, or a core.hooksPath that points at the
# wrong directory.
class TestGitHooks < Minitest::Test
  HOOKS = File.expand_path("../dev/githooks", __dir__)

  def setup
    @dir = Dir.mktmpdir("githooks")
    git("init", "--initial-branch=main")
    git("config", "user.email", "test@example.invalid")
    git("config", "user.name", "Hook Test")
    git("config", "core.hooksPath", HOOKS)
    # A first commit, so every case below has a HEAD to diff against.
    write("README.md", "seed\n")
    git("add", "README.md")
    commit("seed", env: { "PUB4_UNTRACKED" => "1" })
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir && File.directory?(@dir)
  end

  # --- helpers -------------------------------------------------------------

  def git(*args, env: {})
    out, status = Open3.capture2e(env, "git", *args, chdir: @dir)
    [out, status]
  end

  def git!(*args, env: {})
    out, status = git(*args, env:)
    raise "git #{args.join(" ")} failed: #{out}" unless status.success?

    out
  end

  def write(path, body)
    full = File.join(@dir, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, body)
  end

  def commit(message, env: {})
    git("commit", "-m", message, env:)
  end

  def refute_committed(out, status, matching)
    refute status.success?, "the hook allowed the commit:\n#{out}"
    assert_match matching, out
  end

  # --- the hooks are actually installed ------------------------------------

  def test_every_hook_is_executable_and_runnable
    %w[pre-commit pre-push post-commit].each do |hook|
      path = File.join(HOOKS, hook)

      assert File.file?(path), "#{hook} is missing"
      assert File.executable?(path), "#{hook} is not executable — git would skip it silently"

      _out, status = Open3.capture2e(RbConfig.ruby, "-c", path)

      assert status.success?, "#{hook} does not parse"
    end
  end

  # --- 1. a commit spanning two trees is the `git commit -a` signature ------

  def stage_two_trees
    write("MASTER/a.rb", "# a\n")
    write("RAILS/b.rb", "# b\n")
    git!("add", "MASTER/a.rb", "RAILS/b.rb")
  end

  def test_a_cross_tree_commit_is_refused
    stage_two_trees
    out, status = commit("spans two trees")

    refute_committed out, status, /REFUSED — this commit spans 2 trees: MASTER, RAILS/
  end

  def test_the_refusal_names_the_way_out
    stage_two_trees
    out, _status = commit("spans two trees")

    assert_match(/PUB4_CROSS_TREE=1/, out)
    assert_match(/bin\/pub4 worktree/, out, "the refusal should name the actual fix, not only the override")
  end

  def test_the_cross_tree_override_is_honoured
    stage_two_trees
    out, status = commit("spans two trees, deliberately", env: { "PUB4_CROSS_TREE" => "1" })

    assert status.success?, "PUB4_CROSS_TREE=1 did not let the commit through:\n#{out}"
  end

  def test_a_single_tree_commit_passes
    write("MASTER/a.rb", "# a\n")
    git!("add", "MASTER/a.rb")
    out, status = commit("one tree")

    assert status.success?, "an ordinary single-tree commit was refused:\n#{out}"
  end

  # --- 2. untracked files in the tree being committed ----------------------

  def test_an_untracked_file_in_the_committed_tree_is_refused
    write("MASTER/a.rb", "# a\n")
    git!("add", "MASTER/a.rb")
    write("MASTER/forgotten.rb", "# never staged\n")
    out, status = commit("one tree, one file left behind")

    refute_committed out, status, /REFUSED — untracked file\(s\)/
    assert_match(/MASTER\/forgotten\.rb/, out, "the refusal should name the file it is refusing over")
    assert_match(/PUB4_UNTRACKED=1/, out)
  end

  def test_an_untracked_file_in_another_tree_does_not_refuse
    write("MASTER/a.rb", "# a\n")
    git!("add", "MASTER/a.rb")
    write("RAILS/elsewhere.rb", "# another session's\n")
    out, status = commit("one tree")

    assert status.success?, "an untracked file in a tree this commit does not touch blocked it:\n#{out}"
  end

  def test_what_is_left_uncommitted_is_printed_grouped_by_tree
    write("MASTER/a.rb", "# a\n")
    git!("add", "MASTER/a.rb")
    write("RAILS/one.rb", "# 1\n")
    write("RAILS/two.rb", "# 2\n")
    out, _status = commit("one tree")

    assert_match(/leaving uncommitted:.*RAILS \(2\)/, out)
    assert_match(/may belong to another session/, out)
  end

  # --- 3. a move that would half-land --------------------------------------

  def test_a_staged_deletion_beside_an_untracked_twin_is_refused
    write("MASTER/store.rb", "# original\n")
    git!("add", "MASTER/store.rb")
    commit("add store", env: { "PUB4_UNTRACKED" => "1" })

    git!("rm", "--cached", "MASTER/store.rb")
    FileUtils.rm(File.join(@dir, "MASTER/store.rb"))
    write("MASTER/ground/store.rb", "# moved\n")
    out, status = commit("move store")

    refute_committed out, status, /REFUSED — staged deletion \+ untracked twin/
    assert_match(/PUB4_SPLIT_MOVE=1/, out)
  end

  # --- 4. STUDIO ownership -------------------------------------------------

  def test_studio_belongs_to_the_session_that_claimed_it
    write("STUDIO/.session", "other-session\n")
    write("STUDIO/beat.rb", "# a take\n")
    git!("add", "STUDIO/.session", "STUDIO/beat.rb")
    out, status = commit("touch STUDIO")

    refute_committed out, status, /REFUSED — STUDIO is owned by session 'other-session'/
  end

  def test_the_claiming_session_may_commit_studio
    write("STUDIO/.session", "mine\n")
    write("STUDIO/beat.rb", "# a take\n")
    git!("add", "STUDIO/.session", "STUDIO/beat.rb")
    out, status = commit("touch STUDIO", env: { "PUB4_SESSION" => "mine" })

    assert status.success?, "the owning session was refused its own tree:\n#{out}"
  end

  # --- 5. pre-push: a push carries everything beneath it -------------------

  def push_setup
    remote = File.join(@dir, "..", "remote-#{File.basename(@dir)}.git")
    Open3.capture2e("git", "init", "--bare", "--initial-branch=main", remote)
    git!("remote", "add", "origin", remote)
    git!("push", "origin", "main", env: { "PUB4_PUSH_ALL" => "1" })
    remote
  end

  def add_commits(count)
    count.times do |i|
      write("MASTER/c#{i}.rb", "# #{i}\n")
      git!("add", "MASTER/c#{i}.rb")
      out, status = commit("commit #{i}", env: { "PUB4_UNTRACKED" => "1" })
      raise "setup commit failed: #{out}" unless status.success?
    end
  end

  def test_a_push_of_one_commit_is_allowed_and_named
    remote = push_setup
    add_commits(1)
    out, status = git("push", "origin", "main")

    assert status.success?, "a single-commit push was refused:\n#{out}"
    assert_match(/pre-push: publishing/, out, "the one commit being published should still be named")
  ensure
    FileUtils.remove_entry(remote) if remote && File.directory?(remote)
  end

  def test_a_push_of_more_than_one_commit_is_refused
    remote = push_setup
    add_commits(3)
    out, status = git("push", "origin", "main")

    refute status.success?, "a three-commit push was allowed:\n#{out}"
    assert_match(/REFUSED — 3 commits would be published, not 1/, out)
    assert_match(/PUB4_PUSH_ALL=1/, out)
    assert_match(/bin\/pub4 worktree/, out)
  ensure
    FileUtils.remove_entry(remote) if remote && File.directory?(remote)
  end

  def test_the_refusal_lists_every_commit_it_is_holding_back
    remote = push_setup
    add_commits(3)
    out, _status = git("push", "origin", "main")

    3.times { |i| assert_match(/commit #{i}/, out, "commit #{i} was held back without being named") }
    assert_match(/Hook Test/, out, "each held commit should carry its author")
  ensure
    FileUtils.remove_entry(remote) if remote && File.directory?(remote)
  end

  def test_the_push_override_is_honoured
    remote = push_setup
    add_commits(3)
    out, status = git("push", "origin", "main", env: { "PUB4_PUSH_ALL" => "1" })

    assert status.success?, "PUB4_PUSH_ALL=1 did not let the push through:\n#{out}"
  ensure
    FileUtils.remove_entry(remote) if remote && File.directory?(remote)
  end

  # A missing ledger must read as "unknown", never as "foreign", or the first
  # push from a shell without one is a wall of false accusations.
  def test_an_absent_session_ledger_does_not_accuse
    remote = push_setup
    add_commits(3)
    FileUtils.rm_f(File.join(@dir, ".git", "pub4-session-commits"))
    out, _status = git("push", "origin", "main")

    refute_match(/FOREIGN/, out, "with no ledger the hook accused commits of being foreign")
    assert_match(/yours\?/, out)
  ensure
    FileUtils.remove_entry(remote) if remote && File.directory?(remote)
  end

  # --- 6. post-commit keeps the ledger the push guard reads ----------------

  def test_post_commit_records_this_session_so_pre_push_can_mark_foreign_commits
    write("MASTER/a.rb", "# a\n")
    git!("add", "MASTER/a.rb")
    commit("recorded", env: { "PUB4_SESSION" => "session-a" })

    ledger = File.join(@dir, ".git", "pub4-session-commits")

    assert File.file?(ledger), "post-commit wrote no ledger, so pre-push can never mark anything"
    assert_match(/\Asession-a [0-9a-f]+/, File.read(ledger).lines.last.to_s)
  end
end
