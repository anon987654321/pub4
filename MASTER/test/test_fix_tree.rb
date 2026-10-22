# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"
require "open3"

class TestFixTree < Minitest::Test
  BODY = "x" * 500

  def setup
    @root = Dir.mktmpdir("fix-tree")
    write("lib/a.rb", BODY)
    write("lib/a_helper.rb", BODY)
    write("lib/tiny.rb", "x")
    write("lonely/only.rb", BODY)
    write("deep/a/b/c/d/e/f/g.rb", BODY)

    git("init", "-q")
    git("add", ".")
  end

  def teardown = FileUtils.remove_entry(@root)

  def test_the_tree_lists_tracked_files_and_is_deterministic
    first = Master::Fix::Tree.new(root: @root)
    again = Master::Fix::Tree.new(root: @root)

    assert_equal view(first), view(again)
    assert_equal %w[deep/a/b/c/d/e/f/g.rb lib/a.rb lib/a_helper.rb lib/tiny.rb lonely/only.rb], first.files
  end

  def test_sprawl_names_what_it_measures
    sprawl = Master::Fix::Tree.new(root: @root).sprawl

    assert_includes sprawl[:single_file_dirs], "lonely"
    assert_includes sprawl[:tiny_files], "lib/tiny.rb"
    assert_includes sprawl[:deep_dirs], "deep/a/b/c/d/e/f"
    assert_includes sprawl[:name_twins], %w[lib/a.rb lib/a_helper.rb]
  end

  def test_paths_hold_every_file_and_each_directory_above_it
    paths = Master::Fix::Tree.new(root: @root).paths

    assert_includes paths, "deep/a/b"
    assert_includes paths, "lib/a.rb"
    refute_includes paths, "lib/missing.rb"
  end

  def test_a_parent_relative_tree_target_is_normalized_inside_the_repository
    write("RAILS/app.rb", BODY)
    git("add", "RAILS/app.rb")

    tree = Master::Fix::Tree.new(root: @root, target: "../RAILS")

    assert_equal ["RAILS/app.rb"], tree.files
    assert_equal "RAILS", tree.metrics[:target]
  end

  def test_a_target_that_escapes_the_repository_is_rejected
    error = assert_raises(ArgumentError) do
      Master::Fix::Tree.new(root: @root, target: "../../outside")
    end

    assert_match(/outside repository root/, error.message)
  end

  def test_a_git_inventory_failure_is_not_reported_as_an_empty_tree
    Dir.mktmpdir("not-a-repository") do |root|
      File.write(File.join(root, "app.rb"), "class App; end\n")

      error = assert_raises(RuntimeError) { Master::Fix::Tree.new(root:).files }

      assert_match(/tree inventory failed/, error.message)
      assert_match(/not a git repository|outside a work tree/i, error.message)
    end
  end

  def test_a_target_narrows_the_tree
    tree = Master::Fix::Tree.new(root: @root, target: "lib")

    assert_equal %w[lib/a.rb lib/a_helper.rb lib/tiny.rb], tree.files
  end

  private

  def view(tree) = Master::Fix::TreeView.new(tree).render

  def write(path, body)
    full = File.join(@root, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, body)
  end

  def git(*args)
    _out, status = Open3.capture2e("git", "-C", @root, "-c", "user.name=t", "-c", "user.email=t@t", *args)
    raise "git #{args.join(" ")} failed" unless status.success?
  end
end
