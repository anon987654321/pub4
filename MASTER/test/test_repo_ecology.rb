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
      # A real repository: the cache key is HEAD's mtime, found through
      # `git rev-parse --git-path`, and a hand-made .git/HEAD is not a repository
      # git will answer for, so no key and no cache.
      _, status = Open3.capture2e("git", "init", "-q", dir)
      assert status.success?, "git init failed in the fixture"

      first = CountingEcology.new(root: dir)
      first.snapshot

      second = CountingEcology.new(root: dir)
      assert_equal({ "a.rb" => { "b.rb" => 3 }, "b.rb" => { "a.rb" => 3 } }, second.co_change_graph)
      assert_nil second.build_count
    end
  end
end
