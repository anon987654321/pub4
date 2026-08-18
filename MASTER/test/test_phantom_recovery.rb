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
  SCOPES = %i[default test clean ladder style mixed].freeze

  def setup
    SCOPES.each { |scope| Master::PhantomRecovery.reset!(scope:) }
  end

  # A real malfunction, not a phrasing complaint. These tests used "I'll help
  # you with that task now." — gaslighting_preamble, now style_only — so they
  # exercised the ladder with the one detector that must never reach it.
  MALFUNCTION = "the quick brown fox jumps over the lazy dog and keeps going " * 4

  def test_handle_escalates_then_halts
    bus = FakeBus.new
    text = MALFUNCTION

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
    phantom = MALFUNCTION

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
    phantom = MALFUNCTION

    Master::PhantomRecovery.handle(phantom, bus:, scope: :test)
    Master::PhantomRecovery.handle("Done. Tests pass.", bus:, scope: :clean)

    assert_equal :escalate, Master::PhantomRecovery.handle(phantom, bus:, scope: :test)[:action],
                 "a clean response in one scope reset the counter in another"
  end

  # A style complaint must never spend the ladder. gaslighting_preamble matches
  # any reply opening "I can", "I would", "Let me" or "Sure," — ordinary English
  # — so counting it ends the conversation over phrasing.
  def test_a_style_only_finding_never_escalates
    bus = FakeBus.new
    styled = "Let me take a look at that for you."

    5.times do
      result = Master::PhantomRecovery.handle(styled, bus:, scope: :style)
      assert_equal :continue, result[:action],
                   "a style-only finding drove the ladder — five ordinary replies halted the conversation"
    end

    refute bus.events.any? { |event, _| event == "phantom:halt" }
  end

  # Reported, not silently dropped: the dmesg lane and any critique still see it.
  def test_a_style_only_finding_is_still_detected_and_reported
    bus = FakeBus.new
    result = Master::PhantomRecovery.handle("Sure, here is what I found.", bus:, scope: :style)

    assert_includes result[:patterns], "gaslighting_preamble"
    assert bus.events.any? { |event, _| event == "phantom:detected" }
  end

  # A malfunction alongside a style hit is still a malfunction.
  def test_a_mixed_finding_still_escalates
    bus = FakeBus.new
    mixed = "Let me take a look. #{MALFUNCTION}"

    assert_equal :discard, Master::PhantomRecovery.handle(mixed, bus:, scope: :mixed)[:action],
                 "a real malfunction stopped counting because a style pattern appeared beside it"
  end

  # The list is law, so it lives in data/rules.yml rather than in this module.
  def test_the_style_only_list_comes_from_the_rules_file
    assert_includes Master::PhantomRecovery.style_only_detectors, "gaslighting_preamble"
    refute_includes Master::PhantomRecovery.style_only_detectors, "text_repetition_loop"
  end

  def test_judge_agent_calls_master_phantom_recovery
    source = File.read(File.join(Master::ROOT, "lib", "review", "agent.rb"))
    assert_includes source, "Master::PhantomRecovery.handle"
    refute_match(/(?<!Master::)PhantomRecovery\.handle/, source)
  end
end
