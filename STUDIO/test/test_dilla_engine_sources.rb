# frozen_string_literal: true

# Deliberately does NOT load the engine. DillaSources exists so provenance and
# this suite can ask what the engine is made of without booting it, and a test
# that required dilla.rb first would not be testing that property.
require_relative "studio_helper"
require_relative "../dilla/lib/engine_sources"

# Five pieces of code used to answer "which files is the engine made of" and
# gave three different answers. The parse check ran over a corpus that excluded
# every lib/*.rb file; provenance's glob went a level deeper and, when the
# engine split into lib/engine/, dropped 484 of 610 knobs out of every manifest
# without failing anything. The split is gone; the corpus question is not.
class TestEngineSources < Minitest::Test
  def test_it_loads_with_no_dependencies
    # If this file ever grows a require of dilla.rb, ROOT, or a gem, the gate
    # and provenance both start paying a full engine boot to ask a question
    # about filenames.
    source = File.read(File.join(Studio::ROOT, "dilla", "lib", "engine_sources.rb"))
    requires = source.scan(/^\s*require(?:_relative)?\s/)

    assert_empty requires, "engine_sources.rb grew a dependency; it is the one file that must have none"
  end

  def test_every_declared_file_is_on_disk
    missing = DillaSources.all.reject { |path| File.file?(path) }
    assert_empty missing, "DillaSources names files the engine will die requiring: #{missing.inspect}"
  end

  # The split is gone, and it does not come back quietly. A part under
  # lib/engine/ was dead the moment ENGINE_PARTS stopped naming it; now the
  # directory itself is the finding, because the engine is one file.
  def test_the_engine_directory_does_not_come_back
    assert_empty Dir[File.join(DillaSources.root, "lib", "engine", "*.rb")],
                 "lib/engine/ is back — a new feature folds into dilla.rb rather than reopening the split"
  end

  def test_the_corpus_covers_the_entry_point_and_the_support_files
    all = DillaSources.all

    assert_includes all, DillaSources.entry
    assert_operator DillaSources.support.size, :>, 0
    DillaSources.support.each { |path| assert_includes all, path }
    assert_equal all.size, all.uniq.size, "a file is checked twice, which is how two answers stay in agreement"
  end

  def test_the_engine_is_one_file
    # The order the 81 parts loaded in was load-bearing -- constants computed at
    # load time from ones above them -- so it is now the order they sit in.
    entry = File.read(DillaSources.entry)

    assert_operator entry.lines.size, :>, 20_000, "the engine is inline; a small entry means it split again"
    refute_match(%r{require_relative "lib/engine/}, entry, "the entry requires a part that should be inline")
  end

  def test_every_file_in_the_corpus_is_readable_ruby
    DillaSources.all.each do |path|
      assert File.file?(path), "#{path} is in the corpus and not on disk"
      assert_equal ".rb", File.extname(path)
    end
  end

  # The property STUDIO/gate.rb's load probe and this whole suite depend on.
  def test_the_entry_point_guards_its_cli_dispatch
    source = File.read(DillaSources.entry)

    assert_match(/__FILE__\s*==\s*\$PROGRAM_NAME/, source,
                 "without the guard, requiring dilla.rb runs a command and nothing past parse can be checked")
  end
end
