# frozen_string_literal: true

require_relative "test_helper"

class TestDestructiveReview < Minitest::Test
  class FakeDeliberation
    attr_reader :calls

    def initialize(outcome: :pass)
      @outcome = outcome
      @calls = 0
    end

    def review(_payload, context:)
      @calls += 1
      case @outcome
      when :veto
        Master::Result.ok([{ persona: "Skeptic", feedback: "reject reject reject", confidence: 0.2 }])
      when :low
        Master::Result.ok([{ persona: "Skeptic", feedback: "caution", confidence: 0.3 }])
      else
        Master::Result.ok([{ persona: "Maintainer", feedback: "approved", confidence: 0.9 }])
      end
    end
  end

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
    @previous = ENV["MASTER_BLOCKING_REVIEW"]
    ENV["MASTER_BLOCKING_REVIEW"] = "1"
  end

  def teardown
    ENV["MASTER_BLOCKING_REVIEW"] = @previous
  end

  def build_ctx(command: "shell", args: "ls")
    Master::CLI::PipelineContext.build(
      user_message: "/#{command} #{args}",
      intent: :command,
      command:,
      args:,
      destructive_route: true,
    )
  end

  def test_pre_execute_blocks_low_confidence_council
    bus = FakeBus.new
    stage = Master::CLI::Stages::DestructiveReview.new(
      deliberation: FakeDeliberation.new(outcome: :low),
      event_bus: bus,
    )

    result = stage.call(build_ctx)

    refute result.ok?
    assert_equal :policy, result.category
    assert_includes bus.events.map(&:first), "review:blocked"
  end

  def test_pre_execute_passes_high_confidence_council
    bus = FakeBus.new
    stage = Master::CLI::Stages::DestructiveReview.new(
      deliberation: FakeDeliberation.new(outcome: :pass),
      event_bus: bus,
    )

    result = stage.call(build_ctx)

    assert result.ok?
    assert result.value![:review_preapproved]
    assert_includes bus.events.map(&:first), "review:verdict"
  end

  def test_skips_non_destructive_commands
    deliberation = FakeDeliberation.new
    stage = Master::CLI::Stages::DestructiveReview.new(
      deliberation:,
      event_bus: FakeBus.new,
    )
    ctx = Master::CLI::PipelineContext.build(user_message: "/status", intent: :command, command: "status")

    result = stage.call(ctx)

    assert result.ok?
    assert_equal 0, deliberation.calls
  end
end
