# frozen_string_literal: true

require_relative "test_helper"
require "master"
require "open3"

class TestRepoEcology < Minitest::Test
  class CountingEcology < Master::Review::RepoEcology
    attr_reader :build_count

    private

    def build_co_change_graph
      @build_count = (@build_count || 0) + 1
      { "a.rb" => { "b.rb" => 3 }, "b.rb" => { "a.rb" => 3 } }.freeze
    end
  end

  def test_analyze_file_returns_typed_record
    Dir.mktmpdir("repo_ecology_test") do |dir|
      path = File.join(dir, "sample.rb")
      File.write(path, "class Sample\n  def call = true\nend\n")
      ecology = Master::Review::RepoEcology.new(root: dir)

      record = ecology.__send__(:analyze_file, path)

      assert_instance_of Master::Review::RepoEcology::FileRecord, record
      assert_equal "sample.rb", record.path
      assert_equal ".rb", record.ext
      assert record.lines.positive?
      assert record.tokens.include?("sample")
    end
  end

  def test_scan_uses_file_records_for_report
    Dir.mktmpdir("repo_ecology_scan") do |dir|
      File.write(File.join(dir, "sample.rb"), "puts 'ok'\n")
      report = Master::Review::RepoEcology.new(root: dir).scan

      assert_equal 1, report[:files]
      assert_equal 1, report[:extension_mix][".rb"]
      assert report[:score][:value].between?(0, 100)
    end
  end

  def test_snapshot_and_scan_share_memoized_co_change_graph
    Dir.mktmpdir("repo_ecology_graph") do |dir|
      File.write(File.join(dir, "sample.rb"), "puts 'ok'\n")
      ecology = CountingEcology.new(root: dir)

      ecology.snapshot
      report = ecology.scan

      assert_equal 1, ecology.build_count
      assert_equal [{ a: "a.rb", b: "b.rb", count: 3 }], report[:co_change_pairs]
    end
  end

  def test_co_change_graph_persists_between_instances
    Dir.mktmpdir("repo_ecology_cache") do |dir|
      # A real repository: the cache key is the commit SHA returned by
      # `git rev-parse HEAD`, not .git/HEAD's mtime. A branch can advance while
      # .git/HEAD itself remains unchanged.
      _, status = Open3.capture2e("git", "init", "-q", dir)
      assert status.success?, "git init failed in the fixture"

      first = CountingEcology.new(root: dir)
      first.snapshot

      second = CountingEcology.new(root: dir)
      assert_equal({ "a.rb" => { "b.rb" => 3 }, "b.rb" => { "a.rb" => 3 } }, second.co_change_graph)
      assert_nil second.build_count
    end
  def test_co_change_cache_rebuilds_after_head_advances
    Dir.mktmpdir("repo_ecology_cache_refresh") do |dir|
      File.write(File.join(dir, "sample.rb"), "puts :one\n")
      _, status = Open3.capture2e("git", "init", "-q", dir)
      assert status.success?
      _, status = Open3.capture2e("git", "-C", dir, "add", "sample.rb")
      assert status.success?
      _, status = Open3.capture2e(
        "git", "-C", dir, "-c", "user.name=Test", "-c", "user.email=test@example.com",
        "commit", "-qm", "one"
      )
      assert status.success?

      first = CountingEcology.new(root: dir)
      first.snapshot
      cached = CountingEcology.new(root: dir)
      assert_equal 0, cached.instance_variable_get(:@build_count).to_i

      File.write(File.join(dir, "sample.rb"), "puts :two\n")
      _, status = Open3.capture2e("git", "-C", dir, "add", "sample.rb")
      assert status.success?
      _, status = Open3.capture2e(
        "git", "-C", dir, "-c", "user.name=Test", "-c", "user.email=test@example.com",
        "commit", "-qm", "two"
      )
      assert status.success?

      refreshed = CountingEcology.new(root: dir)
      refreshed.co_change_graph
      assert_equal 1, refreshed.build_count
    end
  end

end
