# frozen_string_literal: true

require_relative "test_helper"
require "unwrap_error"

class TestPhantomRecovery < Minitest::Test
  class FakeBus
    attr_reader :events

    def initialize
      @events = []
    end

    def publish(event, payload = {})
      @events << [event, payload]
    end
  end

  def setup
    Master::PhantomRecovery.reset!
  end

  def test_handle_escalates_then_halts
    bus = FakeBus.new
    text = "I'll help you with that task now."

    first = Master::PhantomRecovery.handle(text, bus:, scope: :test)
    assert_equal :discard, first[:action]

    second = Master::PhantomRecovery.handle(text, bus:, scope: :test)
    assert_equal :escalate, second[:action]

    third = Master::PhantomRecovery.handle(text, bus:, scope: :test)
    assert_equal :halt, third[:action]
    assert bus.events.any? { |event, _| event == "phantom:halt" }
  end

  def test_clean_text_continues
    bus = FakeBus.new
    result = Master::PhantomRecovery.handle("Done. Tests pass.", bus:, scope: :clean)
    assert_equal :continue, result[:action]
  end

  def test_judge_agent_calls_master_phantom_recovery
    source = File.read(File.join(Master::ROOT, "lib", "judge", "agent.rb"))
    assert_includes source, "Master::PhantomRecovery.handle"
    refute_match(/(?<!Master::)PhantomRecovery\.handle/, source)
  end
end
