# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

# The cognitive layer, held to the two things that were wrong in its first draft
# and would each have made it look wired while doing nothing.
class TestCognition < Minitest::Test
  Cognition = Master::Cognition

  # A bus with the real glob semantics, because that is the fact under test:
  # EventBus compiles `*` to [^:]* and `**` to .*, so a single star sees only
  # colon-free event names.
  class Bus
    attr_reader :published

    def initialize
      @published = []
      @subscriptions = []
    end

    def subscribe(pattern, &block) = @subscriptions << [pattern, block]

    def publish(event, payload = {})
      enriched = payload.merge(event:)
      @published << enriched
      @subscriptions.each { |pattern, block| block.call(enriched) if glob?(pattern, event.to_s) }
      self
    end

    private

    def glob?(pattern, event)
      Regexp.new("\\A#{Regexp.escape(pattern).gsub('\\*\\*', ".*").gsub('\\*', "[^:]*")}\\z").match?(event)
    end
  end

  class Memory
    attr_reader :rows

    def initialize = @rows = []
    def remember(key, value, type:) = @rows << [key, value, type]
  end

  def test_state_built_from_the_frozen_default_is_still_mutable
    state = Cognition::State.new(Cognition::State::DEFAULT)
    state.affect["valence"] = 0.4
    state.drives["curiosity"] = 0.9

    assert_in_delta 0.4, state.affect["valence"]
    assert_in_delta 0.9, state.drives["curiosity"]
  end

  def test_attention_rises_with_prediction_error
    attention = Cognition::Attention.new
    affect = Cognition::State.new({}).affect
    low = attention.score(event: "event", payload: {}, prediction_error: 0.05, affect:)
    high = attention.score(event: "event", payload: {}, prediction_error: 1.0, affect:)

    assert_operator high, :>, low
  end

  # The bug that would have made the whole layer inert: `*` never matches a
  # colon-namespaced event, and nearly every event MASTER publishes has one.
  def test_the_subscription_reaches_namespaced_events
    Dir.mktmpdir("cognition") do |root|
      bus = Bus.new
      mind = Cognition::Mind.new(root:, bus:)
      bus.publish("tool:after", ok: true)

      assert_equal "tool:after", mind.snapshot.dig("self_model", "last_event"),
                   "a colon-namespaced event must reach the mind — `*` would not have"
    end
  end

  # Perception is silent and writes nothing; tick is the only writer and the
  # only publisher. A layer that published per observation would double every
  # event on a bus it subscribes to all of.
  def test_perception_neither_writes_nor_publishes
    Dir.mktmpdir("cognition") do |root|
      bus = Bus.new
      mind = Cognition::Mind.new(root:, bus:)
      bus.publish("chat:message", ok: true)

      refute_path_exists File.join(root, Cognition::Mind::STATE_PATH)
      assert_equal 1, bus.published.size, "observing must not put another event on the bus"

      mind.tick!

      assert_path_exists File.join(root, Cognition::Mind::STATE_PATH)
      assert(bus.published.any? { |row| row[:event] == "cognition:tick" })
    end
  end

  def test_observation_moves_affect_and_the_working_set
    Dir.mktmpdir("cognition") do |root|
      mind = Cognition::Mind.new(root:, bus: Bus.new)
      mind.observe(event: "chat:message", payload: { ok: true })
      snapshot = mind.snapshot

      assert_equal 1, snapshot.fetch("workspace").size
      assert_operator snapshot.dig("affect", "valence"), :>, 0, "a successful outcome raises valence"
    end
  end

  # The claim the layer must not make, pinned so nothing quietly upgrades it.
  def test_the_self_model_stays_uncertain_about_consciousness
    Dir.mktmpdir("cognition") do |root|
      memory = Memory.new
      mind = Cognition::Mind.new(root:, bus: Bus.new, memory:)
      text = mind.reflect!

      assert_includes text, "unknown about phenomenal consciousness"
      assert_equal 1, memory.rows.size
      assert_equal "general", memory.rows.first.last
    end
  end
end
