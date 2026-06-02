# frozen_string_literal: true

require_relative "test_helper"
require "master"

class TestRepoEcology < Minitest::Test
  class CountingEcology < Master::Judge::RepoEcology
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
      ecology = Master::Judge::RepoEcology.new(root: dir)

      record = ecology.__send__(:analyze_file, path)

      assert_instance_of Master::Judge::RepoEcology::FileRecord, record
      assert_equal "sample.rb", record.path
      assert_equal ".rb", record.ext
      assert record.lines.positive?
      assert record.tokens.include?("sample")
    end
  end

  def test_scan_uses_file_records_for_report
    Dir.mktmpdir("repo_ecology_scan") do |dir|
      File.write(File.join(dir, "sample.rb"), "puts 'ok'\n")
      report = Master::Judge::RepoEcology.new(root: dir).scan

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
end
