# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/core/paths"
require "fileutils"

class TestCorePaths < Minitest::Test
  def paths
    Master::Core::Paths.new(root: Master::ROOT)
  end

  def test_soul_owns_the_sacred_paths
    assert_includes paths.sacred_paths, "data"
    assert_includes paths.sacred_paths, "data/SOUL.md"
    assert_includes paths.sacred_paths, "data/project_context.yml"
    assert_includes paths.sacred_paths, "lib/review/scan"
    assert_includes paths.sacred_paths, "bin/cli"
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
        "absolute:\n  sacred_paths:\n    - data/\n    - bin/cli\n",
      )
      repo_paths = Master::Core::Paths.new(root:)

      assert_includes repo_paths.sacred_paths, "MASTER/data"
      assert repo_paths.sacred?(File.join(root, "MASTER/data/laws.yml"))
      assert repo_paths.sacred?(File.join(root, "MASTER/bin/cli"))
      refute repo_paths.sacred?(File.join(root, "RAILS/app/models/post.rb"))
    end
  end

  def test_path_escape_is_treated_as_protected
    assert paths.sacred?("../outside")
  end
end
