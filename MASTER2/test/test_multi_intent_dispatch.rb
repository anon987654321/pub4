# frozen_string_literal: true

require_relative "test_helper"

class TestMultiIntentDispatch < Minitest::Test
  def test_dispatch_handles_multi_intent_semicolon
    pipeline = MASTER::Pipeline.new(mode: :executor)
    result = MASTER::Commands.dispatch("help; help", pipeline: pipeline)

    assert result.ok?
    assert_equal true, result.value[:multi_intent]
    assert_equal 2, result.value[:items]
  end

  def test_dispatch_handles_multi_intent_newlines
    pipeline = MASTER::Pipeline.new(mode: :executor)
    result = MASTER::Commands.dispatch("help\nhelp", pipeline: pipeline)

    assert result.ok?
    assert_equal true, result.value[:multi_intent]
    assert_equal 2, result.value[:items]
  end
end
