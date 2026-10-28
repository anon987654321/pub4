# frozen_string_literal: true

require_relative "test_helper"
require "operator/parse_sweep"
require "tmpdir"
require "open3"

class TestParseSweep < Minitest::Test
  # A string literal followed on the next line by another with no comma between
  # them is a syntax error that stops MASTER booting.
  MISSING_COMMA = <<~RUBY
    HELP = [
      "/chat quit — disconnect."
      "/chat summarize — ask the model.",
    ].freeze
  RUBY

  def repo(files)
    Dir.mktmpdir("parse-sweep") do |dir|
      Open3.capture2e("git", "init", "-q", dir)
      files.each { |name, body| File.write(File.join(dir, name), body) }
      Open3.capture2e("git", "-C", dir, "add", ".")
      yield dir
    end
  end

  def test_a_missing_comma_is_reported_with_its_file_and_line
    repo("ok.rb" => "puts 1\n", "chat.rb" => MISSING_COMMA) do |dir|
      broken = Operator::ParseSweep.failures(dir)
      assert_equal ["chat.rb"], broken.map(&:path)
      assert_equal 3, broken.first.line
    end
  end

  def test_a_clean_tree_reports_nothing
    repo("ok.rb" => "puts 1\n") { |dir| assert_empty Operator::ParseSweep.failures(dir) }
  end

  def test_a_tracked_file_deleted_from_disk_is_skipped
    repo("gone.rb" => "puts 1\n") do |dir|
      File.delete(File.join(dir, "gone.rb"))
      assert_empty Operator::ParseSweep.failures(dir)
    end
  end

  def test_the_repository_itself_parses
    root = File.expand_path("../..", __dir__)
    assert_empty Operator::ParseSweep.failures(root), "tracked Ruby that does not parse"
  end
end
