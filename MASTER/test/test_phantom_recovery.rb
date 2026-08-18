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

  # Every scope these tests touch, not just :default. The occurrence counter is
  # per-scope process state and Minitest randomises order, so resetting one
  # scope left test_handle_escalates_then_halts able to inherit a count of 3
  # from a neighbour and halt on its first call.
  SCOPES = %i[default test clean ladder].freeze

  def setup
    SCOPES.each { |scope| Master::PhantomRecovery.reset!(scope:) }
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

  # The ladder counts consecutive phantoms, not every phantom the process has
  # ever seen. A clean response between two phantoms must put the next one back
  # at step one; without that the third phantom a process encounters halts it,
  # and so does every phantom after that, for the life of the process.
  #
  # This is not a rare corner. gaslighting_preamble matches any reply opening
  # "I'll", "I can", "I would", "Let me" or "Sure," — so on a live box the
  # budget is spent within minutes and every turn after it returns an error.
  def test_a_clean_response_resets_the_ladder
    bus = FakeBus.new
    phantom = "Let me take a look at that for you."

    assert_equal :discard, Master::PhantomRecovery.handle(phantom, bus:, scope: :ladder)[:action]
    assert_equal :escalate, Master::PhantomRecovery.handle(phantom, bus:, scope: :ladder)[:action]
    assert_equal :continue, Master::PhantomRecovery.handle("Done. Tests pass.", bus:, scope: :ladder)[:action]

    assert_equal :discard, Master::PhantomRecovery.handle(phantom, bus:, scope: :ladder)[:action],
                 "a clean response did not reset the ladder — the next phantom escalated instead of discarding, " \
                 "so the graduated recovery in data/rules.yml can only ever run once per process"
  end

  # Resetting one conversation must not clear another's progress toward escalation.
  def test_the_reset_is_scoped
    bus = FakeBus.new
    phantom = "Sure, here is what I found."

    Master::PhantomRecovery.handle(phantom, bus:, scope: :test)
    Master::PhantomRecovery.handle("Done. Tests pass.", bus:, scope: :clean)

    assert_equal :escalate, Master::PhantomRecovery.handle(phantom, bus:, scope: :test)[:action],
                 "a clean response in one scope reset the counter in another"
  end

  def test_judge_agent_calls_master_phantom_recovery
    source = File.read(File.join(Master::ROOT, "lib", "review", "agent.rb"))
    assert_includes source, "Master::PhantomRecovery.handle"
    refute_match(/(?<!Master::)PhantomRecovery\.handle/, source)
  end
end
