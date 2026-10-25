# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

# The quarantine was decorative, and the escalation chain was a list nothing
# walked. Both were found by tools/method_graph.rb as methods no root reaches,
# and both turned out to be live defects rather than dead code — which is the
# distinction that census exists to make.
class TestProviderQuarantineWiring < Minitest::Test
  Routing = Master::CLI::Routing

  # Records what it is told and answers a score it was given, so the assessment
  # is the only thing under test.
  class StubHealth
    attr_reader :recorded

    def initialize(score) = (@score = score; @recorded = [])
    def record(**row) = @recorded << row
    def score(_model) = @score
    def rank(models) = models
  end

  def manager(score, path)
    Routing::ProviderQuarantine.new(health: StubHealth.new(score), path:)
  end

  # `quarantine` had exactly one caller — record_and_assess — and
  # record_and_assess had none. So nothing ever wrote an entry and
  # `quarantined?` read an empty log for every provider, forever, while
  # RuntimeRegistry#provider_pool and #status both asked it.
  def test_a_failing_provider_is_actually_quarantined
    Dir.mktmpdir("quarantine") do |dir|
      path = File.join(dir, "quarantine.ndjson")
      subject = manager(0.05, path)

      refute subject.quarantined?("cheap-model"), "nothing recorded yet"
      subject.record_and_assess(model: "cheap-model", status: :error)

      assert subject.quarantined?("cheap-model"),
             "a score at or below the threshold must park the provider"
    end
  end

  def test_a_healthy_provider_is_left_alone
    Dir.mktmpdir("quarantine") do |dir|
      subject = manager(0.9, File.join(dir, "quarantine.ndjson"))
      subject.record_and_assess(model: "good-model", status: :ok)

      refute subject.quarantined?("good-model")
    end
  end

  # The outcome still reaches health. Assessment is added, not substituted:
  # routing reads the score, and losing the record would cost more than the
  # quarantine buys.
  def test_the_outcome_still_reaches_health
    Dir.mktmpdir("quarantine") do |dir|
      health = StubHealth.new(0.9)
      subject = Routing::ProviderQuarantine.new(health:, path: File.join(dir, "q.ndjson"))
      subject.record_and_assess(model: "m", status: :ok, latency_ms: 12)

      assert_equal 1, health.recorded.size
      assert_equal({ model: "m", status: :ok, latency_ms: 12, error: nil }, health.recorded.first)
    end
  end

  def test_operator_clear_releases_quarantine_even_with_same_second_timestamps
    Dir.mktmpdir("quarantine-clear") do |dir|
      now = Time.utc(2026, 10, 26, 12, 0, 0)
      subject = Routing::ProviderQuarantine.new(
        health: StubHealth.new(0.05),
        path: File.join(dir, "quarantine.ndjson"),
        now: -> { now },
      )

      subject.quarantine(model: "provider-a", reason: "fixture failure")
      assert subject.quarantined?("provider-a")

      subject.clear("provider-a")

      refute subject.quarantined?("provider-a"),
             "the latest clear event must supersede an earlier quarantine"
    end
  end

  def test_provider_can_be_quarantined_again_after_operator_clear
    Dir.mktmpdir("quarantine-rearm") do |dir|
      now = Time.utc(2026, 10, 26, 12, 0, 0)
      subject = Routing::ProviderQuarantine.new(
        health: StubHealth.new(0.05),
        path: File.join(dir, "quarantine.ndjson"),
        now: -> { now },
      )

      subject.quarantine(model: "provider-a", reason: "first failure")
      subject.clear("provider-a")
      refute subject.quarantined?("provider-a")

      subject.quarantine(model: "provider-a", reason: "new failure")

      assert subject.quarantined?("provider-a"),
             "a new quarantine event after clear must become effective"
    end
  end

  # ESCALATION_CHAIN is cheap → default → strong, and stronger_model read a
  # single static key instead of walking it. Escalating from cheap skipped
  # default; escalating twice asked for the same tier both times, so the
  # depth-2 cap in fallback_chain.rb bought a retry that changed nothing.
  def test_escalation_steps_one_tier_at_a_time
    router = Routing::ModelRouter.allocate

    assert_equal "default", router.next_escalation_tier("cheap")
    assert_equal "strong", router.next_escalation_tier("default")
  end

  # The end of the chain has no next, which is what makes the configured
  # escalation_tier the right fallback rather than a second opinion.
  def test_the_chain_ends
    router = Routing::ModelRouter.allocate

    assert_nil router.next_escalation_tier("strong")
    assert_nil router.next_escalation_tier("not-a-tier")
  end
  def test_router_outcome_reaches_quarantine_health_and_compute_pool
    Dir.mktmpdir("router-quarantine-wiring") do |dir|
      health = StubHealth.new(0.9)
      quarantine = Routing::ProviderQuarantine.new(
        health:, path: File.join(dir, "quarantine.ndjson")
      )
      router = Routing::ModelRouter.allocate
      router.instance_variable_set(:@provider_health, health)
      router.instance_variable_set(:@quarantine, quarantine)
      compute_rows = []
      pool = Object.new
      pool.define_singleton_method(:record) { |**row| compute_rows << row }
      router.instance_variable_set(:@compute_pool, pool)

      router.record_provider_outcome(model: "good-model", status: :success, latency_ms: 12)

      assert_equal 1, health.recorded.size
      assert_equal "good-model", health.recorded.first[:model]
      assert_equal 1, compute_rows.size
      assert_equal :success, compute_rows.first[:status]
    end
  end


end
