# frozen_string_literal: true

require "minitest/autorun"

# RAILS/brgen/AGENTS.md is the topology a reader is sent to when they ask what
# brgen is: one Rails process, a city apex, and namespaced engines on
# subdomains. Assertions on it live here rather than in brgen's own suite
# because brgen's suite runs against the deployed tree on vm23, where the copy
# of this document is whatever the last sync left behind — on 2026-08-21 that
# was a version from two weeks earlier, and the deploy halted on a document
# nobody had edited. The repo is where the document is true or false.
class BrgenAgentNotesTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  NOTES = File.join(ROOT, "brgen/AGENTS.md")

  def notes = @notes ||= File.read(NOTES)

  def test_it_says_one_process_and_names_the_engine_layout
    assert_includes notes, "One Rails process"
    assert_includes notes, "engines/marketplace"
    assert_includes notes, "ENTRIES"
    assert_includes notes, "vowel"
  end

  # Every city apex carries the same verticals, so the document has to show a
  # pair — a reader who sees only brgen.no reads the network as Bergen plus
  # some extras.
  def test_it_shows_the_same_vertical_on_two_cities
    assert_includes notes, "markedsplass.brgen.no"
    assert_includes notes, "marketplace.lsangeles.com"
    assert_includes notes, "dating.brgen.no"
    assert_includes notes, "dating.lsangeles.com"
  end

  def test_it_separates_messenger_and_master_from_the_engines
    assert_includes notes, "messenger.brgen.no"
    assert_includes notes, "ai.brgen.no"
    assert_includes notes, "Not a brgen subapp"
  end
end
