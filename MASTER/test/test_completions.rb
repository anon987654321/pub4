# frozen_string_literal: true

require_relative "test_helper"

# The zsh completion is a second list of commands, so it drifts from the
# registry the moment a command is renamed.
class TestCompletions < Minitest::Test
  COMPLETION = File.expand_path("../completions/_master", __dir__)

  def test_the_master_completion_offers_exactly_the_help_topics_and_exit
    offered = File.read(COMPLETION).scan(/^\s+'([a-z]+):/).flatten

    assert_equal (Master::CLI::CommandRegistry::HELP_TOPICS.keys + ["exit"]).sort, offered.sort
  end
end
