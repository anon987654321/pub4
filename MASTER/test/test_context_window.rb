# frozen_string_literal: true

require_relative "test_helper"
require "master"

class TestContextWindow < Minitest::Test
  def test_public_surface_stays_below_god_class_threshold
    assert_operator Master::CLI::ContextWindow.public_instance_methods(false).size, :<=, 10
  end

  def test_model_context_windows_come_from_registry
    assert_equal 64_000, Master.context_window("deepseek-chat")
    assert_equal 200_000, Master.context_window("anthropic/claude-sonnet-4")
    assert_equal 128_000, Master.context_window("x-ai/grok-4.3")
  end
end
