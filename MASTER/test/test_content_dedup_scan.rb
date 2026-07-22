# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/ground/content_dedup_scan"

class TestContentDedupScan < Minitest::Test
  # Matches OpenCrabs' dedup_scan.rs -- exact duplicate lines across
  # MASTER's own config files, advisory only (see ContentDedupScan's
  # header for why this never auto-fixes).
  def test_finds_a_line_duplicated_across_two_files
    with_fixtures(
      "data/a.yml" => "meaning: this exact sentence appears more than once here\n",
      "data/b.yml" => "meaning: this exact sentence appears more than once here\n",
    ) do |root|
      dups = Master::Ground::ContentDedupScan.scan(root:, files: %w[data/a.yml data/b.yml])

      assert_equal 1, dups.size
      assert_equal 2, dups.first.count
      assert_equal %w[data/a.yml:1 data/b.yml:1], dups.first.locations
    end
  end

  def test_finds_a_line_duplicated_within_one_file
    with_fixtures(
      "data/a.yml" => "meaning: this exact sentence appears more than once here\nsomething else entirely\nmeaning: this exact sentence appears more than once here\n",
    ) do |root|
      dups = Master::Ground::ContentDedupScan.scan(root:, files: %w[data/a.yml])

      assert_equal 1, dups.size
      assert_equal %w[data/a.yml:1 data/a.yml:3], dups.first.locations
    end
  end

  def test_ignores_short_lines_below_the_length_floor
    with_fixtures(
      "data/a.yml" => "status: ok\n",
      "data/b.yml" => "status: ok\n",
    ) do |root|
      dups = Master::Ground::ContentDedupScan.scan(root:, files: %w[data/a.yml data/b.yml])

      assert_empty dups, "short structural lines shouldn't count as meaningful duplication"
    end
  end

  def test_ignores_lines_that_only_appear_once
    with_fixtures(
      "data/a.yml" => "meaning: this line only appears exactly one single time\n",
    ) do |root|
      dups = Master::Ground::ContentDedupScan.scan(root:, files: %w[data/a.yml])

      assert_empty dups
    end
  end

  def test_missing_files_are_skipped_without_error
    Dir.mktmpdir do |root|
      dups = Master::Ground::ContentDedupScan.scan(root:, files: %w[data/does_not_exist.yml])

      assert_empty dups
    end
  end

  private

  def with_fixtures(files)
    Dir.mktmpdir do |root|
      files.each do |rel, content|
        path = File.join(root, rel)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, content)
      end
      yield root
    end
  end
end
