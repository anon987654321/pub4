# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "open3"

# TODO.md, Test coverage: no test named GitOperations. It is the runtime's only
# git surface — status, ahead/behind, and the mutation half (add/commit/push/
# reset --hard/tag/fetch) that autocommit and the deploy path drive.
#
# Every command is `git -C @root_path`, so the whole file is exercised against a
# throwaway repository under Dir.mktmpdir with its own bare remote. Nothing here
# can reach the checkout it is running in, which matters more than usual: one of
# the methods under test is reset_hard.
class GitOperationsTest < Minitest::Test
  def setup
    @tmp = Dir.mktmpdir("git_operations_test")
    @remote = File.join(@tmp, "remote.git")
    @repo = File.join(@tmp, "work")

    git_init_bare(@remote)
    clone(@remote, @repo)
    @git = Master::Io::GitOperations.new(@repo)
  end

  def teardown
    FileUtils.remove_entry(@tmp)
  end

  def sh(*args, chdir:)
    out, status = Open3.capture2e(*args, chdir: chdir)
    raise "#{args.join(" ")} failed: #{out}" unless status.success?

    out
  end

  def git_init_bare(path)
    FileUtils.mkdir_p(path)
    sh("git", "init", "--bare", "--initial-branch=main", ".", chdir: path)
  end

  def clone(remote, path)
    FileUtils.mkdir_p(path)
    sh("git", "clone", remote, ".", chdir: path)
    sh("git", "config", "user.email", "test@example.invalid", chdir: path)
    sh("git", "config", "user.name", "Test", chdir: path)
    sh("git", "config", "commit.gpgsign", "false", chdir: path)
    write("README.md", "first\n")
    sh("git", "add", "-A", chdir: path)
    sh("git", "commit", "-m", "first", chdir: path)
    sh("git", "push", "-u", "origin", "main", chdir: path)
  end

  def write(relative, content)
    path = File.join(@repo, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def test_a_clean_repository_reports_clean
    refute @git.dirty?(".")
    assert_empty @git.status_lines
    assert_equal 0, @git.dirty_count
  end

  def test_status_reflects_an_untracked_file
    write("lib/new.rb", "# new\n")

    assert @git.dirty?("lib/")
    assert_equal 1, @git.dirty_count("lib/")
    # git collapses a wholly-untracked directory to `?? lib/` rather than listing
    # its files, so dirty_count is a count of status lines, not of changed files.
    assert(@git.status_lines("lib/").any? { |line| line.start_with?("?? lib/") })
  end

  def test_a_modified_tracked_file_is_named_in_full
    write("README.md", "first\nchanged\n")

    assert_equal 1, @git.dirty_count("README.md")
    assert(@git.status_lines.any? { |line| line.include?("README.md") })
  end

  # dirty?(path) scopes to a path — a change elsewhere must not make lib/ dirty.
  def test_dirty_is_scoped_to_its_path
    write("docs/notes.md", "x\n")

    assert @git.dirty?(".")
    refute @git.dirty?("lib/")
  end

  def test_head_and_branch_read_the_current_checkout
    assert_match(/\A[0-9a-f]{7,}\z/, @git.head)
    assert_equal "main", @git.branch
  end

  def test_diff_stat_summarises_working_changes
    write("README.md", "first\nsecond\n")

    assert_includes @git.diff_stat, "README.md"
  end

  def test_ahead_behind_counts_against_the_upstream
    assert_equal [0, 0], @git.ahead_behind

    write("README.md", "first\nlocal\n")
    @git.add_all
    @git.commit("local work")

    assert_equal [1, 0], @git.ahead_behind
  end

  # A repository with no upstream must answer [0, 0] rather than raise — the
  # rev-list invocation fails there, and callers treat the pair as a plain number.
  def test_ahead_behind_is_zero_without_an_upstream
    solo = File.join(@tmp, "solo")
    FileUtils.mkdir_p(solo)
    sh("git", "init", "--initial-branch=main", ".", chdir: solo)

    assert_equal [0, 0], Master::Io::GitOperations.new(solo).ahead_behind
  end

  def test_add_all_and_commit_move_head
    before = @git.head
    write("lib/added.rb", "# added\n")
    @git.add_all
    @git.commit("adds a file")

    refute_equal before, @git.head
    refute @git.dirty?(".")
  end

  def test_push_updates_the_remote
    write("lib/pushed.rb", "# pushed\n")
    @git.add_all
    @git.commit("pushes")
    @git.push

    assert_equal [0, 0], @git.ahead_behind
    assert_includes sh("git", "log", "--oneline", chdir: @remote), "pushes"
  end

  def test_fetch_sees_a_new_remote_commit
    other = File.join(@tmp, "other")
    FileUtils.mkdir_p(other)
    sh("git", "clone", @remote, ".", chdir: other)
    sh("git", "config", "user.email", "other@example.invalid", chdir: other)
    sh("git", "config", "user.name", "Other", chdir: other)
    File.write(File.join(other, "README.md"), "first\nfrom other\n")
    sh("git", "commit", "-am", "from other", chdir: other)
    sh("git", "push", chdir: other)

    @git.fetch

    assert_equal [0, 1], @git.ahead_behind
  end

  def test_reset_hard_discards_local_work
    write("README.md", "first\nunwanted\n")
    @git.add_all
    @git.commit("unwanted")

    @git.reset_hard("origin/main")

    assert_equal "first\n", File.read(File.join(@repo, "README.md"))
    assert_equal [0, 0], @git.ahead_behind
  end

  def test_tag_names_the_current_commit
    @git.tag("v-test")

    assert_includes sh("git", "tag", "--list", chdir: @repo), "v-test"
  end
end
