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
end
