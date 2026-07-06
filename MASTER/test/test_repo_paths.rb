# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class RepoPathsTest < Minitest::Test
  def test_repo_root_is_pub4_monorepo
    assert_equal Master::REPO_ROOT, Master.repo_root
    assert_equal File.expand_path("..", Master::ROOT), Master.repo_root
  end

  def test_deploy_path_joins_under_deploy
    path = Master.deploy_path("tools", "postpro", "postpro.rb")
    assert_includes path, "/DEPLOY/tools/postpro/postpro.rb"
    assert File.file?(path)
  end
end