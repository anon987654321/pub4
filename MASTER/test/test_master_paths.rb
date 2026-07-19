# frozen_string_literal: true

require_relative "test_helper"

class MasterPathsTest < Minitest::Test
  def test_paths_resolve_under_master_root
    assert MasterPaths.root.end_with?("/MASTER")
    assert_equal File.expand_path("..", MasterPaths.root), MasterPaths.repo
    assert MasterPaths.data("rules.yml").end_with?("/MASTER/data/rules.yml")
    assert MasterPaths.state("provider_catalog.sqlite3").include?(".master")
  end
end
