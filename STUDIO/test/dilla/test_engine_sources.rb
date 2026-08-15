# frozen_string_literal: true

# Deliberately does NOT load the engine. DillaSources exists so provenance and
# this suite can ask what the engine is made of without booting it, and a test
# that required dilla.rb first would not be testing that property.
require_relative "../helper"
require_relative "../../dilla/lib/engine_sources"

# Five pieces of code used to answer "which files is the engine made of" and
# gave three different answers. The parse check ran over a corpus that excluded
# every lib/*.rb file; provenance's glob went a level deeper and, when the
# engine split into lib/engine/, dropped 484 of 610 knobs out of every manifest
# without failing anything.
class TestEngineSources < Minitest::Test
  def test_it_loads_with_no_dependencies
    # If this file ever grows a require of dilla.rb, ROOT, or a gem, the gate
    # and provenance both start paying a full engine boot to ask a question
    # about filenames.
    source = File.read(File.join(Studio::ROOT, "dilla", "lib", "engine_sources.rb"))
    requires = source.scan(/^\s*require(?:_relative)?\s/)

    assert_empty requires, "engine_sources.rb grew a dependency; it is the one file that must have none"
  end

  def test_every_declared_part_is_on_disk
    missing = DillaSources.parts.reject { |path| File.file?(path) }
    assert_empty missing, "ENGINE_PARTS names files the engine will die requiring: #{missing.inspect}"
  end

  # The other direction: a part on disk that nothing requires is dead code that
  # still parses, which is the shape an autofix leaves behind.
  def test_nothing_in_the_engine_directory_is_unreferenced
    assert_empty DillaSources.unlisted_parts,
                 "in lib/engine/ but not in ENGINE_PARTS, so nothing requires it"
  end

  def test_the_corpus_covers_the_entry_point_and_the_support_files
    all = DillaSources.all

    assert_includes all, DillaSources.entry
    assert_operator DillaSources.support.size, :>, 0
    DillaSources.support.each { |path| assert_includes all, path }
    assert_equal all.size, all.uniq.size, "a file is checked twice, which is how two answers stay in agreement"
  end

  def test_the_part_order_is_declared_once_and_is_load_bearing
    # Constants in these files are computed at load time from ones above them,
    # so the list is an ordering, not a set. Nothing else may re-derive it.
    assert_equal DillaSources::ENGINE_PARTS, DillaSources::ENGINE_PARTS.uniq,
                 "a part required twice re-evaluates constants computed from the ones above it"
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
