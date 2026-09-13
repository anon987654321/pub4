# frozen_string_literal: true

require_relative "test_helper"
require "master"

class TestContextWindow < Minitest::Test
  def test_public_surface_stays_below_god_class_threshold
    assert_operator Master::CLI::ContextWindow.public_instance_methods(false).size, :<=, 10
  end

  # A fake agent that lets a turn append while it is "summarising".
  class SlowAgent
    attr_reader :context
    def initialize(&during) = @during = during
    def ask(_prompt, context:)
      @context = context
      @during&.call
      "- summary"
    end
  end

  def session
    @session ||= Master::Trace::Session.new(root: Dir.mktmpdir("ctx-window"))
  end

  def test_compaction_summarises_a_prefix_and_keeps_the_tail_and_late_turns
    10.times { |i| session.add_message(role: :user, content: "turn #{i}") }
    agent = SlowAgent.new { session.add_message(role: :user, content: "late turn") }
    window = Master::CLI::ContextWindow.new(session:, agent:)

    assert window.send(:compact!, :hard).ok?

    assert_equal 6, agent.context.size, "the last four messages are not sent for summary"
    contents = session.messages.map { |m| m[:content] }
    assert_match(/Context compacted/, contents.first)
    assert_equal ["turn 6", "turn 7", "turn 8", "turn 9", "late turn"], contents.drop(1)
  end

  def test_the_providers_input_count_raises_pressure_past_the_estimate
    session.add_message(role: :user, content: "short")
    agent = SlowAgent.new
    window = Master::CLI::ContextWindow.new(session:, agent:, model_context: 1_000)
    assert_equal :ok, window.check_and_compact!.value

    session.record_input_tokens(950)

    assert_equal :compacted, window.check_and_compact!.value
    assert_equal 0, session.token_pressure - session.token_est, "compaction clears the measured count"
  end

  def test_model_context_windows_come_from_registry
    assert_equal 64_000, Master.context_window("deepseek-chat")
    assert_equal 200_000, Master.context_window("anthropic/claude-sonnet-4")
    assert_equal 128_000, Master.context_window("x-ai/grok-4.3")
  end
end
