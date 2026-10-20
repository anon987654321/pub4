# frozen_string_literal: true

require "test_helper"
require_relative "../lib/fix/governor"

class GovernorTest < Minitest::Test
  Config = Struct.new(:auto?)

  def test_guarded_tool_uses_the_interactive_session_asker
    Fiber[:master_terminal_ask] = ->(prompt:, options:) { "approve" }
    governor = Master::Fix::Governor.new(config: Config.new(false))

    result = governor.check_permit("web_fetch", :guarded, "https://example.com")

    assert result.ok?
  ensure
    Fiber[:master_terminal_ask] = nil
  end

  def test_invalid_terminal_choice_is_a_validation_error
    Fiber[:master_terminal_ask] = ->(prompt:, options:) { "garbage" }
    governor = Master::Fix::Governor.new(config: Config.new(false))

    result = governor.check_permit("web_fetch", :guarded, "https://example.com")

    refute result.ok?
    assert_equal :validation, result.category
  ensure
    Fiber[:master_terminal_ask] = nil
  end
  def test_the_rate_ceiling_comes_from_the_data_and_is_not_three_a_minute
    assert_operator Master::Fix::Governor.rate_limits.fetch("dangerous"), :>, 10
  end

  def test_a_call_over_the_ceiling_is_refused
    governor = Master::Fix::Governor.new(config: Config.new(true))

    Master::Fix::Governor.stub(:rate_limits, { "dangerous" => 2 }) do
      results = Array.new(3) { governor.check_permit("zsh", :dangerous, "ls") }

      assert_equal %i[ok ok rate_limit], results.map { |result| result.ok? ? :ok : result.category }
    end
  end
end
