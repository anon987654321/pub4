# frozen_string_literal: true

require_relative "../test_helper"

class TestReviewBlocking < Minitest::Test
  class FakeBus
    attr_reader :events

    def initialize
      @events = []
    end

    def publish(event, payload = {})
      @events << [event, payload]
    end
  end

  class FakeLint
    def call(ctx)
      Master::Result.ok(ctx.merge(lint_report: [{ severity: "error", message: "broken" }]))
    end
  end

  class FakePrune
    def call(ctx) = Master::Result.ok(ctx)
  end

  def setup
    @previous = ENV["MASTER_BLOCKING_REVIEW"]
    ENV["MASTER_BLOCKING_REVIEW"] = "1"
  end

  def teardown
    ENV["MASTER_BLOCKING_REVIEW"] = @previous
  end

  def test_post_execute_blocks_destructive_route_on_lint_errors
    review = Master::Now::Stages::Review.new(
      council: nil,
      scanner: nil,
      config: {},
      event_bus: FakeBus.new
    )
    review.instance_variable_set(:@lint, FakeLint.new)
    review.instance_variable_set(:@prune, FakePrune.new)

    ctx = Master::Now::PipelineContext.build(
      user_message: "/shell ls",
      intent: :command,
      command: "shell",
      destructive_route: true,
      output: "ran"
    )

    result = review.call(ctx)

    refute result.ok?
    assert_equal :policy, result.category
  end
end