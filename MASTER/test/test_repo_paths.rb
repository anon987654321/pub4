# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class RepoPathsTest < Minitest::Test
  def test_repo_root_is_pub4_monorepo
    assert_equal Master::REPO_ROOT, Master.repo_root
    assert_equal File.expand_path("..", Master::ROOT), Master.repo_root
  end

  def test_tool_path_joins_under_master_tools
    path = Master.tool_path("postpro.rb")
    assert_includes path, "/MASTER/tools/postpro.rb"
    assert File.file?(path)
  end
end
