# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/trace/event_bus"
require_relative "../lib/trace/sensory_state"

class TestSensoryState < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @log = Master::Trace::Log::Event.new(root: @dir)
    @bus = Master::Trace::EventBus.new(event_log: @log)
    Master::Trace::SensoryState.attach!(@bus, root: @dir)
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir && File.directory?(@dir)
  end

  def test_projects_speech_and_fix_state_without_transcript_data
    @bus.publish("tts:playback:start", text: "secret sentence", voice: "jenny")
    state = Master::Trace::SensoryState.snapshot(root: @dir)

    assert_equal "speaking", state["voice"]
    assert_equal "speaking", state["interaction"]
    refute_includes JSON.generate(state), "secret sentence"

    @bus.publish("tts:playback:end")
    @bus.publish("fix_loop:pass_start", pass: 1, files: 10)
    state = Master::Trace::SensoryState.snapshot(root: @dir)
    assert_equal "fixing", state["task"]
    assert_equal "maintenance", state["system"]
  end

  def test_history_is_bounded
    40.times { @bus.publish("heartbeat:tick") }
    state = Master::Trace::SensoryState.snapshot(root: @dir)
    assert_operator state["history"].length, :<=, 32
  end
end
