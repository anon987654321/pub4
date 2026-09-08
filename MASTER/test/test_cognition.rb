# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "yaml"
require "minitest/autorun"

module Master
  module Ground
    module Swallow
      def self.log(*) = nil
    end unless const_defined?(:Swallow)
  end
end

require_relative "../lib/cognition/state"
require_relative "../lib/cognition/attention"
require_relative "../lib/cognition/affect"
require_relative "../lib/cognition/self_model"
require_relative "../lib/cognition/mind"

class TestCognition < Minitest::Test
  class Bus
    attr_reader :published

    def initialize
      @published = []
      @subscriptions = []
    end

    def subscribe(event, &block)
      @subscriptions << [event, block]
    end

    def publish(event, **payload)
      row = payload.merge(event:)
      @published << row
      @subscriptions.each { |name, block| block.call(row) if name == "*" || name == event }
    end
  end

  class Memory
    attr_reader :rows

    def initialize
      @rows = []
    end

    def remember(key, value, type:)
      @rows << [key, value, type]
    end
  end

  def test_state_is_deeply_mutable
    state = Master::Cognition::State.new(Master::Cognition::State::DEFAULT)
    state.affect["valence"] = 0.4
    state.drives["curiosity"] = 0.9
    assert_equal 0.4, state.affect["valence"]
    assert_equal 0.9, state.drives["curiosity"]
  end

  def test_attention_increases_for_prediction_error
    attention = Master::Cognition::Attention.new
    affect = Master::Cognition::State.new(Master::Cognition::State::DEFAULT).affect
    low = attention.score(event: "event", payload: {}, prediction_error: 0.05, affect:)
    high = attention.score(event: "event", payload: {}, prediction_error: 1.0, affect:)
    assert_operator high, :>, low
  end

  def test_mind_builds_workspace_affect_and_self_model_and_persists
    Dir.mktmpdir("master-cognition") do |root|
      bus = Bus.new
      memory = Memory.new
      mind = Master::Cognition::Mind.new(root:, bus:, memory:)

      mind.observe(event: "chat:message", payload: { ok: true, text: "hello" })
      snapshot = mind.snapshot

      assert_equal "chat:message", snapshot.dig("self_model", "last_event")
      assert_equal 1, snapshot.fetch("workspace").size
      assert snapshot.dig("affect", "valence").positive?
      assert File.file?(File.join(root, ".master/cognition/state.yml"))
    end
  end

  def test_reflection_is_recorded
    Dir.mktmpdir("master-cognition") do |root|
      memory = Memory.new
      mind = Master::Cognition::Mind.new(root:, bus: Bus.new, memory:)
      text = mind.reflect!

      assert_includes text, "phenomenal consciousness"
      assert_equal 1, memory.rows.size
      assert_equal "general", memory.rows.first.last
    end
  end
end
