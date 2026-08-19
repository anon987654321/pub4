# frozen_string_literal: true

require "fileutils"
require_relative "test_helper"

class TestGrokTranscript < Minitest::Test
  FIXTURES = File.expand_path("fixtures/grok", __dir__)

  def test_extract_chat_history_last_turn
    path = File.join(FIXTURES, "chat_history.jsonl")
    text = Master::Io::GrokTranscript.extract(path)
    assert_equal "This is the longer final assistant reply we want spoken.", text
  end

  def test_extract_updates_last_turn
    dir = Dir.mktmpdir("grok-updates-")
    path = File.join(dir, "updates.jsonl")
    File.write(path, File.read(File.join(FIXTURES, "updates.jsonl")))
    text = Master::Io::GrokTranscript.extract(path)
    assert_equal "Latest assistant message.", text
  ensure
    FileUtils.remove_entry(dir) if dir
  end

  def test_resolve_path_prefers_chat_history
    dir = Dir.mktmpdir("grok-transcript-")
    updates = File.join(dir, "updates.jsonl")
    chat = File.join(dir, "chat_history.jsonl")
    File.write(updates, File.read(File.join(FIXTURES, "updates.jsonl")))
    File.write(chat, File.read(File.join(FIXTURES, "chat_history.jsonl")))

    resolved = Master::Io::GrokTranscript.resolve_path(updates)
    assert_equal chat, resolved
    assert_equal "This is the longer final assistant reply we want spoken.",
                 Master::Io::GrokTranscript.extract(updates)
  ensure
    FileUtils.remove_entry(dir) if dir
  end

  def test_extract_empty_path
    assert_equal "", Master::Io::GrokTranscript.extract("")
  end
end
