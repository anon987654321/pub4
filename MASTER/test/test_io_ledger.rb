# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "tmpdir"
require "fileutils"

# The .master ledgers fail closed on read: file, found schema, expected
# schema, in that order, in the message. The board before this contract
# rescued every read error into an empty board and saved the emptiness
# back over the ledger on the next write.
class TestIoLedger < Minitest::Test
  def setup
    @root = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def ledger_path = File.join(@root, "ledger.json")

  def write_ledger(payload, path: ledger_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.pretty_generate(payload))
  end

  def test_missing_file_reads_as_fresh
    assert_nil Master::Io::Ledger.read(ledger_path, schema: 1)
  end

  def test_matching_schema_returns_the_parsed_object
    write_ledger({ schema: 1, ideas: [] })
    data = Master::Io::Ledger.read(ledger_path, schema: 1)
    assert_equal [], data["ideas"]
  end

  def test_wrong_schema_refuses_with_file_found_and_expected
    write_ledger({ schema: 2 })
    error = assert_raises(Master::Io::Ledger::SchemaMismatch) do
      Master::Io::Ledger.read(ledger_path, schema: 1)
    end
    [ledger_path, "2", "1"].each { |part| assert_includes error.message, part.to_s }
  end

  def test_malformed_json_refuses
    FileUtils.mkdir_p(@root)
    File.write(ledger_path, "{not json")
    assert_raises(Master::Io::Ledger::Malformed) { Master::Io::Ledger.read(ledger_path, schema: 1) }
  end

  def test_non_object_ledger_refuses
    write_ledger([1, 2])
    assert_raises(Master::Io::Ledger::Malformed) { Master::Io::Ledger.read(ledger_path, schema: 1) }
  end

  def board_path
    File.join(@root, ".master", "content_board.json")
  end

  def test_board_with_a_stale_schema_refuses_instead_of_coming_up_empty
    write_ledger({ schema: 0, cards: [] }, path: board_path)
    assert_raises(Master::Io::Ledger::SchemaMismatch) { Master::Content::Board.new(root: @root) }
  end

  def test_board_with_a_corrupt_file_refuses_instead_of_coming_up_empty
    FileUtils.mkdir_p(File.dirname(board_path))
    File.write(board_path, "{broken")
    assert_raises(Master::Io::Ledger::Malformed) { Master::Content::Board.new(root: @root) }
  end

  def test_board_round_trips_through_the_checked_reader
    board = Master::Content::Board.new(root: @root)
    assert_empty board.cards
    board.add(Master::Content::Card.new(
                title: "Verify the ledger contract", brief: "Reads refuse closed",
                audience: "maintainer"
              ))
    reloaded = Master::Content::Board.new(root: @root)
    assert_equal 1, reloaded.cards.size
    assert_equal "Verify the ledger contract", reloaded.cards.first.title
  end
end
