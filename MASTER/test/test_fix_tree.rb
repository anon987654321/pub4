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

  def test_aesthetic_signals_find_ugly_names_without_flagging_clean_names
    write("lib/__old.rb", BODY)
    write("lib/legacy_utils.rb", BODY)
    write("lib/too___many.rb", BODY)
    write("lib/clean_name.rb", BODY)
    git("add", ".")

    ugly = Master::Fix::Tree.new(root: @root).sprawl[:ugly_names]

    assert_includes ugly, "lib/__old.rb"
    assert_includes ugly, "lib/legacy_utils.rb"
    assert_includes ugly, "lib/too___many.rb"
    refute_includes ugly, "lib/clean_name.rb"
  end

  def test_concept_scatter_requires_three_owners_and_ignores_framework_entrypoints
    %w[ai fix voice].each do |owner|
      write("lib/#{owner}/dispatch_policy.rb", BODY)
      write("lib/#{owner}/engine.rb", BODY)
    end
    %w[ai fix].each do |owner|
      write("lib/#{owner}/shared_cache.rb", BODY)
    end
    git("add", ".")

    scatter = Master::Fix::Tree.new(root: @root).sprawl[:concept_scatter]

    assert_includes scatter.map(&:first), "dispatch_policy"
    refute_includes scatter.map(&:first), "shared_cache"
    refute_includes scatter.map(&:first), "engine"
  end

  def test_rails_helper_conventions_do_not_count_as_ugly_names
    write("RAILS/brgen/app/helpers/application_helper.rb", BODY)
    write("RAILS/brgen/test/test_helper.rb", BODY)
    write("RAILS/brgen/test/support_face_manifest_helper.rb", BODY)
    write("RAILS/brgen/app/services/reply_utils.rb", BODY)
    git("add", ".")

    ugly = Master::Fix::Tree.new(root: @root).sprawl[:ugly_names]

    refute_includes ugly, "RAILS/brgen/app/helpers/application_helper.rb"
    refute_includes ugly, "RAILS/brgen/test/test_helper.rb"
    refute_includes ugly, "RAILS/brgen/test/support_face_manifest_helper.rb"
    assert_includes ugly, "RAILS/brgen/app/services/reply_utils.rb"
  end

  def test_concept_scatter_ignores_standard_rails_templates_and_readmes
    %w[brgen amber bsdports].each do |app|
      write("RAILS/#{app}/app/views/posts/index.html.erb", BODY)
      write("RAILS/#{app}/README.md", BODY)
      write("RAILS/#{app}/app/controllers/application_controller.rb", BODY)
      write("RAILS/#{app}/Gemfile", BODY)
      write("RAILS/#{app}/Rakefile", BODY)
      write("RAILS/#{app}/config/database.yml", BODY)
      write("RAILS/#{app}/config/environment.rb", BODY)
      write("RAILS/#{app}/config/environments/production.rb", BODY)
      write("RAILS/#{app}/db/seeds.rb", BODY)
      write("RAILS/#{app}/app/models/dispatch_policy.rb", BODY)
    end
    %w[dating maps marketplace].each do |engine|
      write("RAILS/brgen_#{engine}/app/controllers/#{engine}/base_controller.rb", BODY)
    end
    git("add", ".")

    scatter = Master::Fix::Tree.new(root: @root).sprawl[:concept_scatter].map(&:first)

    %w[index.html README application_controller Gemfile Rakefile database environment production seeds base_controller].each do |stem|
      refute_includes scatter, stem
    end
    assert_includes scatter, "dispatch_policy"
  end

  def test_depth_tax_only_flags_important_concepts_beyond_depth_three
    write("deep/a/b/core.rb", BODY)
    write("lib/core/fold.rb", BODY)
    git("add", ".")

    tax = Master::Fix::Tree.new(root: @root).sprawl[:depth_tax]

    assert_includes tax, "deep/a/b/core.rb"
    refute_includes tax, "lib/core/fold.rb"
  end

  def test_root_clutter_waits_until_more_than_eighteen_files
    assert_empty Master::Fix::Tree.new(root: @root).sprawl[:root_clutter]

    19.times { |index| write("root_#{index}.rb", BODY) }
    git("add", ".")

    assert_equal 19, Master::Fix::Tree.new(root: @root).sprawl[:root_clutter].size
  end

  def test_root_clutter_is_relative_to_the_selected_target
    19.times { |index| write("lib/root_#{index}.rb", BODY) }
    git("add", ".")

    lib_tree = Master::Fix::Tree.new(root: @root, target: "lib")
    repository_tree = Master::Fix::Tree.new(root: @root)

    assert_equal 19, lib_tree.sprawl[:root_clutter].size
    assert_empty repository_tree.sprawl[:root_clutter]
  end

  def test_single_file_dirs_excludes_the_selected_target_root
    write("lib/tiny_area/root.rb", BODY)
    write("lib/tiny_area/only/one.rb", BODY)
    git("add", ".")

    tree = Master::Fix::Tree.new(root: @root, target: "lib/tiny_area")

    refute_includes tree.sprawl[:single_file_dirs], "lib/tiny_area"
    assert_includes tree.sprawl[:single_file_dirs], "lib/tiny_area/only"
    assert_equal 0, tree.directories.find { |dir| dir.path == "lib/tiny_area" }.depth
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
