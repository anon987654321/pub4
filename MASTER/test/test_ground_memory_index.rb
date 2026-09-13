# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "json"

# Ground::MemoryIndex tokenises markdown under its directories into a JSON index;
# Ground::MemorySearch scores that index by log term frequency and is what
# ContextProvider's memory_search provider serves. Both take their paths as
# arguments, so every case here runs in a temporary directory.
class TestGroundMemoryIndex < Minitest::Test
  def with_dirs
    Dir.mktmpdir("memory_index") do |root|
      notes = File.join(root, "notes")
      FileUtils.mkdir_p(notes)
      index = Master::Ground::MemoryIndex.new(
        root:, dirs: [notes, File.join(root, "missing")], index_path: File.join(root, "idx", "index.json"),
      )
      yield root, notes, index
    end
  end

  def test_the_default_dirs_name_only_directories_the_tree_uses
    refute Master::Ground::MemoryIndex::DEFAULT_DIRS.any? { |dir| dir.end_with?("data/claude") },
           "data/claude does not exist; indexing it is a claim with no files behind it"
  end

  def test_rebuild_indexes_markdown_and_tolerates_a_missing_directory
    with_dirs do |_root, notes, index|
      File.write(File.join(notes, "relayd.md"), "# Relayd notes\nrelayd relayd header limit\n")
      File.write(File.join(notes, "skip.txt"), "relayd\n")

      docs = index.rebuild!

      assert_equal ["notes/relayd.md"], docs.keys
      doc = docs.fetch("notes/relayd.md")
      assert_equal "Relayd notes", doc["title"]
      assert_equal 3, doc.dig("terms", "relayd")
      assert_equal docs, index.load_index, "the index on disk is what rebuild returned"
    end
  end

  def test_rebuild_keeps_an_unchanged_entry_and_refreshes_a_changed_one
    with_dirs do |_root, notes, index|
      path = File.join(notes, "a.md")
      File.write(path, "alpha\n")
      first = index.rebuild!.fetch("notes/a.md")

      assert_equal first, index.rebuild!.fetch("notes/a.md")

      File.write(path, "bravo\n")
      second = index.rebuild!.fetch("notes/a.md")
      refute_equal first["hash"], second["hash"]
      assert_equal({ "bravo" => 1 }, second["terms"])
    end
  end

  def test_a_corrupt_index_reads_as_empty
    with_dirs do |root, _notes, index|
      FileUtils.mkdir_p(File.join(root, "idx"))
      File.write(index.index_path, "{not json")

      assert_equal({}, index.load_index)
    end
  end

  def test_search_ranks_by_term_frequency_and_rebuilds_an_empty_index
    with_dirs do |_root, notes, index|
      File.write(File.join(notes, "many.md"), "# Many\npledge pledge pledge unveil\n")
      File.write(File.join(notes, "one.md"), "# One\npledge\n")
      File.write(File.join(notes, "none.md"), "# None\nrelayd\n")

      hits = Master::Ground::MemorySearch.new(index:).search("pledge unveil")

      assert_equal %w[notes/many.md notes/one.md], hits.map { |doc| doc["path"] }
      assert_in_delta Math.log(4) + Math.log(2), hits.first["score"], 1e-9
    end
  end

  def test_search_ignores_terms_shorter_than_three_characters
    with_dirs do |_root, notes, index|
      File.write(File.join(notes, "a.md"), "ok go\n")

      assert_empty Master::Ground::MemorySearch.new(index:).search("ok go")
      assert_equal "Memory search: no hits for \"ok\".", Master::Ground::MemorySearch.new(index:).brief("ok")
    end
  end
end
