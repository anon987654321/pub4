# frozen_string_literal: true

require_relative "test_helper"

class TestAutocomplete < Minitest::Test
  def test_commands_list
    assert MASTER::Autocomplete::COMMANDS.include?("help")
    assert MASTER::Autocomplete::COMMANDS.include?("exit")
    assert MASTER::Autocomplete::COMMANDS.include?("refactor")
  end

  def test_complete_matches_prefix
    matches = MASTER::Autocomplete.complete("ref")
    assert_includes matches, "refactor"
  end

  def test_complete_no_matches
    matches = MASTER::Autocomplete.complete("xyz")
    refute_includes matches, "refactor"
  end

  def test_complete_empty_returns_all
    matches = MASTER::Autocomplete.complete("")
    assert matches.any?
  end
end
