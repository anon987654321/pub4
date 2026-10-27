# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"

class TestCorePaths < Minitest::Test
  def paths
    Master::Core::Constitution::Paths.new(root: Master::ROOT)
  end

  def test_soul_owns_the_sacred_paths
    refute_includes paths.sacred_paths, "data/"
    refute_includes paths.sacred_paths, "data/soul.yml"
    refute_includes paths.sacred_paths, "lib/review/scan/"
    assert_includes paths.sacred_paths, "data/SOUL.md"
    assert_includes paths.sacred_paths, "data/project_context.yml"
    assert_includes paths.sacred_paths, "lib/ground/pledge.rb"
    assert_includes paths.sacred_paths, "bin/master"
  end

  def test_authored_fix_code_is_not_sacred
    refute paths.sacred?("lib/fix/fix_loop.rb")
    refute paths.sacred?("lib/core/paths.rb")
  end

  def test_repository_root_resolves_sacred_paths_under_master
    Dir.mktmpdir("core-paths") do |root|
      FileUtils.mkdir_p(File.join(root, "MASTER/data"))
      File.write(
        File.join(root, "MASTER/data/soul.yml"),
        "absolute:\n  sacred_paths:\n    - data/\n    - bin/master\n",
      )
      repo_paths = Master::Core::Constitution::Paths.new(root:)

      assert_includes repo_paths.sacred_paths, "MASTER/data/"
      assert repo_paths.sacred?(File.join(root, "MASTER/data/laws.yml"))
      assert repo_paths.sacred?(File.join(root, "MASTER/bin/master"))
      refute repo_paths.sacred?(File.join(root, "RAILS/app/models/post.rb"))
    end
  end

  def test_path_escape_is_treated_as_protected
    assert paths.sacred?("../outside")
  end

  def test_missing_soul_manifest_fails_closed_for_queries_commits_and_load
    Dir.mktmpdir("core-paths-missing-soul") do |root|
      data_dir = File.join(root, "data")
      FileUtils.mkdir_p(data_dir)
      File.write(File.join(data_dir, "laws.yml"), "{}\n")
      repo_paths = Master::Core::Constitution::Paths.new(root:)

      assert_raises(Errno::ENOENT) { repo_paths.sacred_paths }
      assert repo_paths.sacred?("data/laws.yml")
      assert_includes repo_paths.commit_refusal("data/laws.yml"), "constitution unreadable"
      assert_includes repo_paths.commit_refusal("data/spine.yml"), "constitution unreadable"
      assert_raises(Errno::ENOENT) do
        Master::Core::Constitution.load(data_dir:, workspace_root: root)
      end
    end
  end

  def test_empty_sacred_path_declaration_fails_closed_including_ratchet_ceiling
    Dir.mktmpdir("core-paths-empty-soul") do |root|
      data_dir = File.join(root, "data")
      FileUtils.mkdir_p(data_dir)
      File.write(File.join(data_dir, "soul.yml"), "absolute:\n  sacred_paths: []\n")
      repo_paths = Master::Core::Constitution::Paths.new(root:)

      assert_raises(RuntimeError) { repo_paths.sacred_paths }
      assert repo_paths.sacred?("lib/fix/fix_loop.rb")
      assert_includes repo_paths.commit_refusal("data/spine.yml"), "constitution unreadable"
    end
  end

  def test_blank_sacred_path_entries_fail_closed
    Dir.mktmpdir("core-paths-blank-soul") do |root|
      data_dir = File.join(root, "data")
      FileUtils.mkdir_p(data_dir)
      File.write(File.join(data_dir, "soul.yml"), "absolute:\n  sacred_paths:\n    - \"\"\n")
      repo_paths = Master::Core::Constitution::Paths.new(root:)

      assert_raises(RuntimeError) { repo_paths.sacred_paths }
      assert_includes repo_paths.commit_refusal("data/spine.yml"), "constitution unreadable"
    end
  end

  def test_malformed_soul_manifest_fails_closed
    Dir.mktmpdir("core-paths-malformed-soul") do |root|
      data_dir = File.join(root, "data")
      FileUtils.mkdir_p(data_dir)
      File.write(File.join(data_dir, "soul.yml"), "absolute: [\n")
      repo_paths = Master::Core::Constitution::Paths.new(root:)

      assert repo_paths.sacred?("lib/fix/fix_loop.rb")
      assert_includes repo_paths.commit_refusal("data/spine.yml"), "constitution unreadable"
    end
  end

  def test_unreadable_soul_manifest_fails_closed
    Dir.mktmpdir("core-paths-unreadable-soul") do |root|
      repo_paths = Master::Core::Constitution::Paths.new(root:)
      repo_paths.stub(:sacred_paths, -> { raise Errno::EACCES, "Permission denied" }) do
        assert repo_paths.sacred?("lib/fix/fix_loop.rb")
        assert_includes repo_paths.commit_refusal("data/spine.yml"), "constitution unreadable"
      end
    end
  end

end
