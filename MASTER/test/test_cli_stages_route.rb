# frozen_string_literal: true

require_relative "test_helper"

# Stages::Route resolves a slash command or hands the turn to the agent, and on
# a miss suggests the nearest registered verb by edit distance.
class TestCliStagesRoute < Minitest::Test
  Ctx = Struct.new(:intent, :command, keyword_init: true) do
    def merge(**extra) = to_h.merge(extra)
  end

  def route(*names) = Master::CLI::Stages::Route.new(commands: names.to_h { |n| [n, :"#{n}_handler"] }, agent: :agent)

  def command(name) = Ctx.new(intent: :command, command: name)

  def test_a_registered_command_resolves_to_its_handler
    result = route("status", "review").call(command("status"))

    assert result.ok?
    assert_equal :status_handler, result.value![:handler]
  end

  def test_a_typo_suggests_the_nearest_command
    result = route("status", "review", "rollback").call(command("stauts"))

    refute result.ok?
    assert_equal "unknown command: /stauts -- did you mean /status?", result.message
  end

  def test_nothing_close_enough_suggests_nothing
    result = route("status", "review").call(command("zzzzzzzz"))

    assert_equal "unknown command: /zzzzzzzz", result.message
  end

  # The distance table is seeded with the row and column indices; a wrong seed
  # makes an insertion at the start cost nothing and suggests far too much.
  def test_levenshtein_matches_the_textbook_distances
    router = route
    distance = ->(a, b) { router.send(:levenshtein, a, b) }

    assert_equal 0, distance.call("", "")
    assert_equal 3, distance.call("", "abc")
    assert_equal 3, distance.call("abc", "")
    assert_equal 3, distance.call("kitten", "sitting")
    assert_equal 2, distance.call("stauts", "status")
    assert_equal 1, distance.call("review", "reviews")
  end

  def test_llm_intent_routes_to_the_agent
    result = route.call(Ctx.new(intent: :llm, command: nil))

    assert_equal :agent, result.value![:handler]
  end
end
