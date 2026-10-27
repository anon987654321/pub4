# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/operator/worktree"
require "fileutils"
require "open3"
require "tmpdir"

class TestOperatorWorktree < Minitest::Test
  def setup
    @workspace = Dir.mktmpdir("operator-worktree-")
    @root = File.join(@workspace, "repo")
    FileUtils.mkdir_p(@root)
    git!("init", "-q")
    git!("checkout", "-qb", "main")
    git!("config", "user.name", "Test Operator")
    git!("config", "user.email", "test@example.invalid")
    File.write(File.join(@root, "README.md"), "base\n")
    git!("add", "README.md")
    git!("commit", "-qm", "base")
    @manager = Operator::Worktree.new(root: @root)
  end

  def teardown
    FileUtils.remove_entry(@workspace) if @workspace && File.directory?(@workspace)
  end

  def test_creates_a_sibling_worktree_on_a_named_branch
    entry = @manager.create("repair-123", base: "main")

    assert_equal "work/repair-123", entry.branch
    assert File.directory?(entry.path)
    refute entry.path.start_with?("#{@root}#{File::SEPARATOR}")
    assert_equal git!("rev-parse", "main").strip, entry.revision
    assert_equal ["repair-123"], @manager.list.map(&:name)
  end

  def test_remove_keeps_the_branch
    entry = @manager.create("kept")
    removed = @manager.remove("kept")

    assert_equal entry.path, removed.fetch(:path)
    refute File.exist?(entry.path)
    assert_equal "work/kept", git!("branch", "--list", "work/kept").strip
  end

  def test_dirty_source_is_refused_unless_its_exclusion_is_explicit
    File.write(File.join(@root, "README.md"), "uncommitted edit\n")

    error = assert_raises(Operator::Worktree::Error) { @manager.create("refused") }
    assert_match(/source checkout is dirty/, error.message)

    entry = @manager.create("explicit", base: "main", allow_dirty_source: true)
    assert_equal "base\n", File.read(File.join(entry.path, "README.md"))
    assert_equal "uncommitted edit\n", File.read(File.join(@root, "README.md"))
  end

  def test_removal_refuses_to_discard_dirty_worktree_changes
    entry = @manager.create("dirty-tree")
    File.write(File.join(entry.path, "unfinished.rb"), "unfinished\n")

    assert_raises(Operator::Worktree::Error) { @manager.remove("dirty-tree") }
    assert File.exist?(File.join(entry.path, "unfinished.rb"))
    assert File.directory?(entry.path)
  end

  def test_list_and_remove_refuse_a_symlinked_managed_root
    outside = File.join(@workspace, "outside")
    FileUtils.mkdir_p(outside)
    File.symlink(outside, @manager.managed_root)

    assert_raises(Operator::Worktree::Error) { @manager.list }
    assert_raises(Operator::Worktree::Error) { @manager.remove("anything") }
  end

  def test_rejects_traversal_and_does_not_overwrite_an_existing_branch
    assert_raises(Operator::Worktree::Error) { @manager.create("../outside") }
    git!("branch", "work/existing")
    assert_raises(Operator::Worktree::Error) { @manager.create("existing") }
  end

  def test_command_supports_create_list_and_remove
    assert_equal 0, Operator::Worktree.command(["cli-test", "--base", "main"], root: @root)
    assert_equal 0, Operator::Worktree.command(["list"], root: @root)
    assert_equal 0, Operator::Worktree.command(["remove", "cli-test"], root: @root)
  end

  private

  def git!(*args)
    output, status = Open3.capture2e("git", *args, chdir: @root)
    raise "git #{args.join(" ")} failed: #{output}" unless status.success?

    output
  end
end
