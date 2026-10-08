# frozen_string_literal: true

require "minitest/autorun"
require "master"

class TtsWorkerContractTest < Minitest::Test
  def test_edge_worker_rejects_nil_process_arguments_before_spawn
    speech = Master::Voice::Speech
    messages = []

    speech.stub(:warn_tts, ->(message) { messages << message }) do
      result = speech.synthesize_edge_oneshot(
        text: "hello",
        voice_name: nil,
        style_config: { rate: "+0%", pitch: "+0Hz" },
        audio_path: "/tmp/m_tts_probe.mp3",
      )
      assert_nil result
    end

    assert messages.any? { |message| message.include?("edge worker error: ArgumentError") }
    assert messages.any? { |message| message.include?("voice") }
  ensure
    File.delete("/tmp/m_tts_probe.mp3") if File.exist?("/tmp/m_tts_probe.mp3")
  end
end
