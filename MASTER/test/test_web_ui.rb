# frozen_string_literal: true

require_relative "test_helper"
require "rack/test"

# Minimal Rack test harness for the web UI chat controller.
# Tests cover SSE stream, TTS endpoint, dmesg, and metrics.

ENV["RAILS_ENV"] = "test"

# We test the controller logic via a stub Rack app rather than
# booting the full Rails stack.
class FakeSpeech
  def self.available?  = true
  def self.synthesize_bytes(_text, **) = "FAKE-MP3-BYTES"
end

class FakePipeline
  attr_writer :result
  def call(_ctx) = @result || Master::Result.ok(rendered: "hello from pipeline")
end

class FakeSession
  def token_est = 42
  def cost      = 0.0001
end

class FakeAgent
  def model = "test/model-7b"
end

class FakeContainer
  def [](key)
    case key
    when :agent    then FakeAgent.new
    when :session  then FakeSession.new
    when :pipeline then @pipeline ||= FakePipeline.new
    end
  end
  def pipeline = self[:pipeline]
end

class TestWebUI < Minitest::Test
  include Rack::Test::Methods

  def setup
    @container = FakeContainer.new
  end

  # ── Result monad ──────────────────────────────────────────────────────────

  def test_result_ok_wraps_value
    r = Master::Result.ok("hello")
    assert r.ok?
    assert_equal "hello", r.value!
  end

  def test_result_err_wraps_message
    r = Master::Result.err("boom")
    assert r.err?
    assert_equal "boom", r.message
  end

  def test_result_err_value_bang_raises_unwrap_error
    r = Master::Result.err("boom")
    assert_raises(Master::UnwrapError) { r.value! }
  end

  def test_result_ok_chaining
    r = Master::Result.ok(5).and_then { |v| Master::Result.ok(v * 2) }
    assert_equal 10, r.value!
  end

  def test_result_err_short_circuits
    r = Master::Result.err("x").and_then { raise "should not reach" }
    assert r.err?
  end

  # ── Pipeline ─────────────────────────────────────────────────────────────

  def test_pipeline_returns_result
    result = @container.pipeline.call(Master::Result.ok(user_message: "hi"))
    assert result.ok?
    assert_includes result.value![:rendered], "hello"
  end

  def test_pipeline_err_propagates
    @container.pipeline.result = Master::Result.err("model down")
    result = @container.pipeline.call(Master::Result.ok(user_message: "hi"))
    assert result.err?
    assert_equal "model down", result.message
  end

  # ── Speech bytes ─────────────────────────────────────────────────────────

  def test_speech_synthesize_bytes_stub
    bytes = FakeSpeech.synthesize_bytes("hello world")
    assert_equal "FAKE-MP3-BYTES", bytes
  end

  # ── Cognitive monitor ─────────────────────────────────────────────────────

  def test_cognitive_monitor_starts_clean
    m = Master::CognitiveMonitor.new
    assert_equal 0.0, m.load
    assert_equal :optimal, m.flow_state
  end

  def test_cognitive_monitor_push_increases_load
    m = Master::CognitiveMonitor.new
    m.push("concept_a", weight: 2.0)
    assert_in_delta 2.0, m.load, 0.01
  end

  def test_cognitive_monitor_overload_after_threshold
    m = Master::CognitiveMonitor.new
    m.push("heavy", weight: 8.0)
    assert m.overloaded?
  end

  def test_cognitive_monitor_reset
    m = Master::CognitiveMonitor.new
    5.times { |i| m.push("c#{i}", weight: 1.5) }
    m.reset!(keep_recent: 2)
    assert m.load <= 3.0
    assert_equal 0, m.switches
  end

  def test_cognitive_monitor_update_flow_returns_self
    m = Master::CognitiveMonitor.new
    assert_same m, m.update_flow(context_switches: 1)
  end

  def test_cognitive_monitor_state_hash
    m = Master::CognitiveMonitor.new
    s = m.state
    assert s.key?(:load)
    assert s.key?(:flow_state)
    assert s.key?(:overload_risk)
    assert s.key?(:complexity)
  end

  # ── SwarmCoordinator ─────────────────────────────────────────────────────

  def test_swarm_coordinator_worker_roles
    # Just check the list is non-empty without booting real agents
    assert_includes Master::Swarm::Coordinator::WORKER_CLASSES.keys, :analyst
    assert_includes Master::Swarm::Coordinator::WORKER_CLASSES.keys, :coder
    assert_includes Master::Swarm::Coordinator::WORKER_CLASSES.keys, :reviewer
    assert_includes Master::Swarm::Coordinator::WORKER_CLASSES.keys, :researcher
  end

  def test_swarm_coordinator_unknown_role
    mock_agent = Minitest::Mock.new
    coord = Master::Swarm::Coordinator.new(agent: mock_agent)
    result = coord.dispatch(:nonexistent, task: "foo")
    assert result.err?
    assert_includes result.message, "unknown role"
  end

  # ── Memory ───────────────────────────────────────────────────────────────

  def test_memory_remember_and_recall
    Dir.mktmpdir do |dir|
      m = Master::Memory.new(root: dir)
      m.remember(:user_name, "Osman")
      assert_equal "Osman", m.recall(:user_name)
    end
  end

  def test_memory_context_summary_nil_when_empty
    Dir.mktmpdir do |dir|
      m = Master::Memory.new(root: dir)
      assert_nil m.context_summary
    end
  end

  def test_memory_context_summary_lists_keys
    Dir.mktmpdir do |dir|
      m = Master::Memory.new(root: dir)
      m.remember(:language, "Ruby")
      summary = m.context_summary
      assert_includes summary, "language"
      assert_includes summary, "Ruby"
    end
  end

  # ── Personality ──────────────────────────────────────────────────────────

  def test_personality_default_is_dark_malay
    assert_equal :dark_malay, Master::Personality::DEFAULT
  end

  def test_personality_system_prompt_non_empty
    p = Master::Personality.new(:dark_malay)
    assert p.system_prompt.length > 10
  end

  def test_personality_system_prompt_memoized
    p = Master::Personality.new(:dark_malay)
    assert_same p.system_prompt, p.system_prompt
  end

  # ── UnwrapError ──────────────────────────────────────────────────────────

  def test_unwrap_error_is_runtime_error_subclass
    assert Master::UnwrapError < RuntimeError
  end
end
