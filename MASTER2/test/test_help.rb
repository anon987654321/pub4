# frozen_string_literal: true

require_relative "test_helper"

class TestHelp < Minitest::Test
  def test_commands_defined
    assert MASTER::Help::COMMANDS.key?(:help)
    assert MASTER::Help::COMMANDS.key?(:exit)
    assert MASTER::Help::COMMANDS.key?(:refactor)
  end

  def test_tips_exist
    assert MASTER::Help::TIPS.any?
  end

  def test_tip_returns_string
    tip = MASTER::Help.tip
    assert_kind_of String, tip
  end

  def test_autocomplete_matches
    matches = MASTER::Help.autocomplete("ref")
    assert_includes matches, "refactor"
  end

  def test_autocomplete_no_match
    matches = MASTER::Help.autocomplete("xyz")
    assert_empty matches
  end
end
