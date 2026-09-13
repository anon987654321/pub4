# frozen_string_literal: true

require_relative "test_helper"
require "json"

# MemoryIndex is what MemorySearch ranks against: one entry per markdown file,
# its title, its top terms and a content hash that lets a rebuild keep an
# unchanged entry instead of re-reading it.
class TestGroundMemoryIndex < Minitest::Test
  def setup
    @root = Dir.mktmpdir("memory_index_")
    @notes = File.join(@root, "notes")
    FileUtils.mkdir_p(File.join(@notes, "deep"))
    File.write(File.join(@notes, "relayd.md"), "intro\n# Relayd limits\nrelayd relayd header header ab\n")
    File.write(File.join(@notes, "deep", "untitled.md"), "no heading here\n")
    File.write(File.join(@notes, "skip.txt"), "not markdown\n")
    @index = Master::Ground::MemoryIndex.new(root: @root, dirs: [@notes], index_path: File.join(@root, "idx", "i.json"))
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def test_indexes_markdown_only_with_titles_and_term_counts
    docs = @index.rebuild!

    assert_equal ["notes/deep/untitled.md", "notes/relayd.md"], docs.keys.sort
    assert_equal "Relayd limits", docs["notes/relayd.md"]["title"]
    assert_equal "untitled.md", docs["notes/deep/untitled.md"]["title"]
    assert_equal 3, docs["notes/relayd.md"]["terms"]["relayd"]
    refute docs["notes/relayd.md"]["terms"].key?("ab"), "terms shorter than three characters are noise"
  end

  def test_the_index_is_written_and_read_back
    @index.rebuild!

    assert_equal @index.rebuild!, @index.load_index
    assert File.file?(File.join(@root, "idx", "i.json"))
  end

  def test_an_unchanged_file_keeps_its_previous_entry
    @index.rebuild!
    stale = @index.load_index
    stale["notes/relayd.md"]["title"] = "kept from the last build"
    File.write(@index.index_path, JSON.generate(stale))

    assert_equal "kept from the last build", @index.rebuild!["notes/relayd.md"]["title"]
    File.write(File.join(@notes, "relayd.md"), "# Changed\n")
    assert_equal "Changed", @index.rebuild!["notes/relayd.md"]["title"]
  end

  def test_a_corrupt_index_reads_empty
    FileUtils.mkdir_p(File.dirname(@index.index_path))
    File.write(@index.index_path, "{broken")

    assert_equal({}, @index.load_index)
  end
end
