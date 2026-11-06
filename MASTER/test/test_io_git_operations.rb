# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "open3"

# GitOperations is the runtime's only git surface — status, ahead/behind, and
# the mutation half (add/commit/push) that autocommit and the deploy path drive.
#
# Every command is `git -C @root_path`, so the whole file is exercised against a
# throwaway repository under Dir.mktmpdir with its own bare remote. Nothing here
# can reach the checkout it is running in.
class GitOperationsTest < Minitest::Test
  # Receipts land here rather than in the runtime event log. down: an event whose
  # durable write fails, as a full disk would.
  class Bus
    attr_reader :events

    def initialize(down: nil)
      @down = down
      @events = []
    end

    def publish_required(event, payload)
      raise IOError, "event log down" if event == @down

      @events << [event, payload]
    end
  end

  def setup
    @tmp = Dir.mktmpdir("git_operations_test")
    @remote = File.join(@tmp, "remote.git")
    @repo = File.join(@tmp, "work")

    git_init_bare(@remote)
    clone(@remote, @repo)
    @bus = Bus.new
    @git = git_with(@bus)
  end

  def git_with(bus) = Master::Io::GitOperations.new(@repo, receipts: Master::Trace::ToolObserver.new(bus:))

  def teardown
    FileUtils.remove_entry(@tmp)
  end

  def sh(*args, chdir:)
    out, status = Open3.capture2e(*args, chdir:)
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
    # Commits refuse sacred paths and fail closed without a constitution to name them.
    write("MASTER/data/soul.yml", "absolute:\n  sacred_paths:\n    - data/soul.yml\n")
    sh("git", "add", "-A", chdir: path)
    sh("git", "commit", "-m", "first", chdir: path)
    sh("git", "push", "-u", "origin", "main", chdir: path)
  end

  def remote_head(branch)
    sh("git", "--git-dir", @remote, "rev-parse", "--short", "refs/heads/#{branch}", chdir: @repo).strip
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

  def test_changed_paths_include_a_deleted_tracked_file
    write("lib/deleted.rb", "# deleted\n")
    sh("git", "add", "lib/deleted.rb", chdir: @repo)
    sh("git", "commit", "-m", "add deleted fixture", chdir: @repo)
    FileUtils.rm_f(File.join(@repo, "lib/deleted.rb"))

    assert_includes @git.changed_paths, "lib/deleted.rb"
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
    @git.commit("local work", paths: ["README.md"])

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

  def test_commit_moves_head
    before = @git.head
    write("lib/added.rb", "# added\n")
    @git.commit("adds a file", paths: ["lib/added.rb"])

    refute_equal before, @git.head
    refute @git.dirty?(".")
  end

  def test_commit_normalizes_subject_case_prefix_and_layout
    write("lib/style.rb", "# style\n")

    @git.commit(
      "fix:  remove   noisy title.\n\nThe body states only what changed.",
      paths: ["lib/style.rb"],
    )

    assert_equal "Remove noisy title", sh("git", "log", "-1", "--format=%s", chdir: @repo).strip
    assert_includes sh("git", "log", "-1", "--format=%B", chdir: @repo), "The body states only what changed."
  end

  # The index is shared with every session in the checkout: a path someone else
  # staged, and a file nobody named, both stay out of the commit.
  def test_commit_takes_only_the_named_paths
    write("lib/mine.rb", "# mine\n")
    write("lib/staged.rb", "# theirs, staged\n")
    write("lib/loose.rb", "# theirs, untracked\n")
    sh("git", "add", "lib/staged.rb", chdir: @repo)

    @git.commit("mine only", paths: ["lib/mine.rb"])

    committed = sh("git", "show", "--name-only", "--format=", "HEAD", chdir: @repo).lines.map(&:chomp)
    assert_equal ["lib/mine.rb"], committed
    assert_includes sh("git", "diff", "--cached", "--name-only", chdir: @repo), "lib/staged.rb"
  end

  # A pre-commit hook that refuses is not a commit, so ops:commit must not be
  # published for one.
  def test_a_refused_commit_raises
    hook = File.join(@repo, ".git", "hooks", "pre-commit")
    File.write(hook, "#!/bin/sh\nexit 1\n")
    File.chmod(0o755, hook)
    write("lib/refused.rb", "# refused\n")

    assert_raises(RuntimeError) { @git.commit("refused", paths: ["lib/refused.rb"]) }
  end

  def test_commit_refuses_paths_outside_the_runtime_root
    assert_raises(ArgumentError) { @git.commit("escape", paths: ["../outside.rb"]) }
    assert_raises(ArgumentError) { @git.commit("absolute", paths: [File.join(@repo, "outside.rb")]) }
  end

  def test_commit_uses_a_nul_pathspec_file_for_large_path_sets
    paths = Array.new(20_000) { |i| "lib/generated/#{i.to_s.rjust(5, "0")}/#{("x" * 32)}.rb" }
    argv = []
    pathspecs = []

    @git.define_singleton_method(:git!) do |*args|
      argv << args
      argument = args.find { |value| value.start_with?("--pathspec-from-file=") }
      pathspecs << File.binread(argument.delete_prefix("--pathspec-from-file=")) if argument
      ""
    end

    @git.commit("bulk change", paths:)

    assert_equal 2, argv.length
    assert_equal paths, pathspecs.first.split("\0").reject(&:empty?)
    refute argv.flatten.any? { |arg| paths.include?(arg) }, "large path sets must not become argv entries"
  end

  def test_commit_refuses_without_paths
    write("lib/any.rb", "# any\n")

    assert_raises(ArgumentError) { @git.commit("everything", paths: []) }
  end

  # ls-files names paths from -C's directory, so a runtime living in a
  # subdirectory of its checkout gets paths it can hand straight back to commit.
  def test_changed_paths_are_relative_to_a_subdirectory_root
    write("sub/tracked.rb", "# tracked\n")
    sh("git", "add", "sub/tracked.rb", chdir: @repo)
    sh("git", "commit", "-m", "sub", chdir: @repo)
    write("sub/tracked.rb", "# changed\n")
    write("sub/lib/new.rb", "# new\n")
    write("outside.md", "x\n")

    assert_equal ["lib/new.rb", "tracked.rb"], Master::Io::GitOperations.new(File.join(@repo, "sub")).changed_paths.sort
  end

  def declare_sacred
    write("MASTER/data/soul.yml", "absolute:\n  sacred_paths:\n    - data/laws.yml\n    - data/soul.yml\n")
    write("MASTER/data/laws.yml", "a: 1\n")
    write("MASTER/data/spine.yml", "spine: 1\n")
  end

  # Every runtime commit goes through git!, so a sacred path is refused there whichever
  # writer changed it: named, listed in a pathspec file, or only staged.
  def test_a_commit_naming_a_sacred_path_is_refused
    declare_sacred

    error = assert_raises(RuntimeError) { @git.commit("laws", paths: ["MASTER/data/laws.yml"]) }
    assert_includes error.message, "data/laws.yml is sacred: no automated writer may change it"
    assert_empty sh("git", "diff", "--cached", "--name-only", chdir: @repo), "a refusal stages nothing"
    assert_raises(RuntimeError) { @git.commit("soul", paths: ["MASTER/data/soul.yml"]) }
    assert_raises(RuntimeError) { @git.git!("commit", "-m", "laws", "--", "MASTER/data/laws.yml") }
    sh("git", "add", "MASTER/data/laws.yml", chdir: @repo)
    assert_raises(RuntimeError) { @git.git!("commit", "-m", "staged laws") }
    assert_equal "first", sh("git", "log", "-1", "--format=%s", chdir: @repo).strip
  end

  # The ratchet ceiling is runtime-written data, not sacred, so it commits beside the change it sponsors.
  def test_the_ratchet_ceiling_and_ordinary_paths_still_commit
    declare_sacred
    write("MASTER/lib/grown.rb", "# grown\n")

    @git.commit("grow", paths: ["MASTER/data/spine.yml", "MASTER/lib/grown.rb"])

    assert_equal "Grow", sh("git", "log", "-1", "--format=%s", chdir: @repo).strip
  end

  # Only runtime commits pass through git!; a person's own commit of the laws is untouched.
  def test_a_person_still_commits_a_sacred_path_with_plain_git
    declare_sacred
    sh("git", "add", "MASTER/data/laws.yml", chdir: @repo)
    sh("git", "commit", "-m", "Amend the laws", "--", "MASTER/data/laws.yml", chdir: @repo)

    assert_equal "Amend the laws", sh("git", "log", "-1", "--format=%s", chdir: @repo).strip
  end

  def test_push_updates_the_remote
    write("lib/pushed.rb", "# pushed\n")
    @git.commit("pushes", paths: ["lib/pushed.rb"])
    @git.push

    assert_equal [0, 0], @git.ahead_behind
    assert_includes sh("git", "log", "--oneline", chdir: @remote), "Pushes"
  end

  def test_push_target_uses_current_topic_branch_even_when_it_tracks_main
    sh("git", "checkout", "-b", "work/fix-topic", chdir: @repo)
    sh("git", "branch", "--set-upstream-to", "origin/main", "work/fix-topic", chdir: @repo)
    main_before = sh("git", "--git-dir", @remote, "rev-parse", "refs/heads/main", chdir: @repo).strip
    write("topic.rb", "# topic\n")
    @git.commit("topic repair", paths: ["topic.rb"])

    assert_equal ["origin", "HEAD:work/fix-topic"], @git.push_target
    @git.push

    assert_equal main_before, sh("git", "--git-dir", @remote, "rev-parse", "refs/heads/main", chdir: @repo).strip
    assert_equal @git.head, remote_head("work/fix-topic")
  end

  def test_first_push_of_a_topic_branch_does_not_require_an_upstream
    sh("git", "checkout", "-b", "work/fresh-topic", chdir: @repo)
    write("fresh-topic.rb", "# fresh\n")
    @git.commit("fresh topic", paths: ["fresh-topic.rb"])

    assert_equal ["origin", "HEAD:work/fresh-topic"], @git.push_target
    @git.push

    assert_equal @git.head, remote_head("work/fresh-topic")
  end

  def push_from_another_clone(file, content)
    other = File.join(@tmp, "other")
    FileUtils.mkdir_p(other)
    sh("git", "clone", @remote, ".", chdir: other)
    sh("git", "config", "user.email", "other@example.invalid", chdir: other)
    sh("git", "config", "user.name", "Other", chdir: other)
    File.write(File.join(other, file), content)
    sh("git", "add", file, chdir: other)
    sh("git", "commit", "-m", "from other", chdir: other)
    sh("git", "push", chdir: other)
  end

  # Another session pushed first: ours lands on top of theirs, and a file
  # left uncommitted in this checkout is still there afterwards.
  def test_push_rebases_over_a_commit_pushed_meanwhile
    push_from_another_clone("other.rb", "# other\n")
    write("lib/ours.rb", "# ours\n")
    @git.commit("ours", paths: ["lib/ours.rb"])
    write("pending.rb", "# not committed\n")

    @git.push

    assert_equal [0, 0], @git.ahead_behind
    assert_equal %w[Ours from], sh("git", "log", "--format=%s", "-2", chdir: @remote).lines.map { _1.split.first }
    assert File.file?(File.join(@repo, "pending.rb"))
  end

  def test_push_raises_when_the_rebase_conflicts
    push_from_another_clone("README.md", "theirs\n")
    write("README.md", "ours\n")
    @git.commit("ours", paths: ["README.md"])

    assert_raises(RuntimeError) { @git.push }
    refute File.directory?(File.join(@repo, ".git", "rebase-merge")), "the conflicted rebase is aborted"
  end

  def test_ahead_behind_sees_a_fetched_remote_commit
    other = File.join(@tmp, "other")
    FileUtils.mkdir_p(other)
    sh("git", "clone", @remote, ".", chdir: other)
    sh("git", "config", "user.email", "other@example.invalid", chdir: other)
    sh("git", "config", "user.name", "Other", chdir: other)
    File.write(File.join(other, "README.md"), "first\nfrom other\n")
    sh("git", "commit", "-am", "from other", chdir: other)
    sh("git", "push", chdir: other)

    sh("git", "fetch", chdir: @repo)

    assert_equal [0, 1], @git.ahead_behind
  end

  def test_a_commit_leaves_a_receipt_with_neither_its_message_nor_its_paths
    write("notes/private-name.md", "x\n")
    @git.commit("Mention the secret plan", paths: ["notes/private-name.md"])

    tools = @bus.events.map { |event, payload| [event, payload[:tool], payload[:status]] }
    assert_equal [["tool:execution:before", "git_add", nil], ["tool:execution:after", "git_add", "success"],
                  ["tool:execution:before", "git_commit", nil], ["tool:execution:after", "git_commit", "success"]], tools
    refute_match(/secret plan|private-name/, @bus.events.inspect)
  end

  def test_no_durable_before_event_means_no_commit
    write("README.md", "first\nsecond\n")
    git = git_with(Bus.new(down: "tool:execution:before"))

    assert_raises(IOError) { git.commit("Second line", paths: ["README.md"]) }
    assert_equal "first", sh("git", "log", "-1", "--format=%s", chdir: @repo).strip
  end
end
