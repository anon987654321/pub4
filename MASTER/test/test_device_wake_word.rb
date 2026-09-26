# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"

class TestDeviceWakeWord < Minitest::Test
  def test_enable_normalizes_phrases
    Dir.mktmpdir("wake-word") do |root|
      wake = Master::Device::WakeWord.new(root:, which: ->(_cmd) { true })
      wake.enable!(phrases: ["Hey MASTER", " hey master "])

      Master::Device.stub(:android?, true) do
        Master::Device.stub(:termux?, true) do
          assert wake.enabled?
        end
      end
      assert_equal ["hey master"], wake.phrases
    end
  end

  def test_match_accepts_a_phrase_inside_transcription
    Dir.mktmpdir("wake-word") do |root|
      wake = Master::Device::WakeWord.new(root:, which: ->(_cmd) { true })
      wake.enable!(phrases: ["hey mochi"])

      assert_equal "hey mochi", wake.send(:match, "Hey Mochi, are you there?")
      assert_nil wake.send(:match, "hello there")
    end
  end

  def test_disabled_listener_does_not_require_microphone
    Dir.mktmpdir("wake-word") do |root|
      wake = Master::Device::WakeWord.new(root:, which: ->(_cmd) { true })

      wake.send(:write_state, "enabled" => false)
      # The listener checks tool availability once, then sleeps without opening
      # the microphone while disabled.
      wake = Master::Device::WakeWord.new(root:, which: ->(_cmd) { true }, sleeper: ->(_seconds) { raise "stop" })
      assert_raises(RuntimeError) { wake.run_forever }
    end
  end
end
