#!/usr/bin/env ruby
# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"
require_relative "../lib/cli"

class TestCLIConstants < Minitest::Test
  def setup
    @cli = MASTER::CLI.new(quiet: true)
  end

  def test_color_constants_are_defined
    assert_equal "\e[0m", MASTER::CLI::Constants::C_RESET
    assert_equal "\e[31m", MASTER::CLI::Constants::C_RED
    assert_equal "\e[32m", MASTER::CLI::Constants::C_GREEN
  end

  def test_icon_constants_are_defined
    assert_equal "✓", MASTER::CLI::Constants::ICON_OK
    assert_equal "✗", MASTER::CLI::Constants::ICON_ERR
    assert_equal "!", MASTER::CLI::Constants::ICON_WARN
  end

  def test_quotes_array_is_frozen
    assert MASTER::CLI::Constants::QUOTES.frozen?
    assert MASTER::CLI::Constants::QUOTES.size == 10
  end

  def test_adjectives_and_nouns_are_frozen
    assert MASTER::CLI::Constants::ADJECTIVES.frozen?
    assert MASTER::CLI::Constants::NOUNS.frozen?
    assert MASTER::CLI::Constants::ADJECTIVES.size == 10
    assert MASTER::CLI::Constants::NOUNS.size == 10
  end

  def test_achievements_hash_is_frozen
    assert MASTER::CLI::Constants::ACHIEVEMENTS.frozen?
    assert MASTER::CLI::Constants::ACHIEVEMENTS.key?(:first_command)
    assert_equal "First Steps", MASTER::CLI::Constants::ACHIEVEMENTS[:first_command][:name]
  end

  def test_aliases_hash_is_frozen
    assert MASTER::CLI::Constants::ALIASES.frozen?
    assert_equal "queue", MASTER::CLI::Constants::ALIASES['q']
    assert_equal "help", MASTER::CLI::Constants::ALIASES['h']
  end

  def test_commands_array_is_frozen
    assert MASTER::CLI::Constants::COMMANDS.frozen?
    assert_includes MASTER::CLI::Constants::COMMANDS, "ask"
    assert_includes MASTER::CLI::Constants::COMMANDS, "help"
  end

  def test_config_constants_are_defined
    assert_equal 100, MASTER::CLI::Constants::HISTORY_LIMIT
    assert_equal 0.01, MASTER::CLI::Constants::EASTER_EGG_CHANCE
    assert_equal 3600, MASTER::CLI::Constants::UPTIME_THRESHOLD
  end

  def test_beautify_guides_are_defined
    assert MASTER::CLI::Constants::BEAUTIFY_GUIDES.frozen?
    assert MASTER::CLI::Constants::BEAUTIFY_GUIDES.key?('ruby')
    assert MASTER::CLI::Constants::BEAUTIFY_GUIDES.key?('javascript')
    assert_includes MASTER::CLI::Constants::BEAUTIFY_GUIDES['ruby'], "Ruby style principles"
  end

  def test_cli_class_includes_constants
    # CLI class should include Constants module, making them accessible
    assert_equal "✓", MASTER::CLI::ICON_OK
    assert_equal "queue", MASTER::CLI::ALIASES['q']
  end

  def test_constants_available_in_cli_instance
    # Constants should be available to CLI instances via the module
    assert_equal "\e[0m", @cli.class::C_RESET
    assert_equal "✓", @cli.class::ICON_OK
  end
end
