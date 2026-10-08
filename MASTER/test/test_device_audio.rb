# frozen_string_literal: true

require_relative "test_helper"
require "tempfile"

class TestDeviceAudio < Minitest::Test
  Audio = Master::Device::Audio

  def setup
    @old_android = Master::Device.method(:android?)
    @old_executable = Audio.method(:executable?)
    @old_run = Audio.method(:run)
  end

  def teardown
    Master::Device.define_singleton_method(:android?, &@old_android)
    Audio.define_singleton_method(:executable?, &@old_executable)
    Audio.define_singleton_method(:run, &@old_run)
  end

  def test_android_audio_availability_is_capability_based
    Master::Device.define_singleton_method(:android?) { true }
    Audio.define_singleton_method(:executable?) { |command| command == Audio::TTS_COMMAND }

    assert Audio.tts_available?
    refute Audio.media_player_available?
    assert Audio.available?
  end

  def test_speak_uses_the_canonical_termux_tts_command
    calls = []
    Master::Device.define_singleton_method(:android?) { true }
    Audio.define_singleton_method(:executable?) { |command| command == Audio::TTS_COMMAND }
    Audio.define_singleton_method(:run) { |*argv| calls << argv; true }

    assert Audio.speak("hello")
    assert_equal [[Audio::TTS_COMMAND, "-s", "MUSIC", "hello"]], calls
  end

  def test_media_playback_and_stop_use_the_same_boundary
    calls = []
    Master::Device.define_singleton_method(:android?) { true }
    Audio.define_singleton_method(:executable?) { |command| command == Audio::MEDIA_PLAYER }
    Audio.define_singleton_method(:run) { |*argv| calls << argv; true }

    Tempfile.create(["master-audio", ".mp3"]) do |file|
      file.write("audio")
      file.flush

      assert Audio.play(file.path)
      assert Audio.stop
      assert_equal [
        [Audio::MEDIA_PLAYER, "play", file.path],
        [Audio::MEDIA_PLAYER, "stop"],
      ], calls
    end
  end
end
