# frozen_string_literal: true

require_relative "test_helper"
require "master"

class TestRepoEcology < Minitest::Test
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
end
