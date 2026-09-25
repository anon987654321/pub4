# frozen_string_literal: true

require_relative "test_helper"
require "master"

# frozen_string_literal: true
class MasterPathsTest < Minitest::Test
  def test_paths_resolve_under_master_root
    assert MasterPaths.root.end_with?("/MASTER")
    assert_equal File.expand_path("..", MasterPaths.root), MasterPaths.repo
    assert MasterPaths.data("rules.yml").end_with?("/MASTER/data/rules.yml")
    assert MasterPaths.state("provider_catalog.sqlite3").include?(".master")
  end
end

# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class RepoPathsTest < Minitest::Test
  def test_repo_root_is_pub4_monorepo
    assert_equal Master::REPO_ROOT, Master.repo_root
    assert_equal File.expand_path("..", Master::ROOT), Master.repo_root
  end
end

# frozen_string_literal: true
require "fileutils"

class TestRepoMap < Minitest::Test
  def test_brief_respects_token_budget
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib"))
      10.times { |index| File.write(File.join(dir, "lib", "file_#{index}.rb"), "puts :ok\n") }

      rows = Master::Ground::Map::Repo.new(root: dir).brief("file", limit: 10, token_limit: 8)

      assert rows.any?
      assert_operator rows.join("\n").bytesize, :<=, 40
    end
  end
end
