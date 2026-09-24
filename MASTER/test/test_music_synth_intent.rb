# frozen_string_literal: true

require_relative "test_helper"

# Where a sound request goes. Every sink is stubbed: nothing here reaches a
# speaker, a file under ~, or dilla.
class TestMusicSynthIntent < Minitest::Test
  INTENT = Master::Io::MediaIntent

  def test_render_writes_the_waveform_to_a_file
    seen = nil
    captured_path = nil
    Master::Music::Synth.stub(:render, ->(shape:, hz:, destination:) do
      seen = [shape, hz]
      captured_path = destination
      destination
    end) do
      result = INTENT.dispatch("render a square wave")
      assert result.ok?
      assert_equal [:square, 440.0], seen
      assert_equal captured_path, result.value[:path]
    end
  end

  def test_deep_tone_uses_low_pitch
    seen = nil
    Master::Music::Synth.stub(:render, ->(shape:, hz:, destination:) do
      seen = hz
      destination
    end) do
      INTENT.dispatch("make a deep sine wave")
    end
    assert_equal 110.0, seen
  end

  # "play" is the speakers: the tone streams live and no file is written.
  def test_play_streams_the_tone_live_and_writes_nothing
    played = nil
    rendered = false
    Master::Music::Realtime.stub(:play, ->(shape:, hz:, seconds:) { played = [shape, hz, seconds] }) do
      Master::Music::Synth.stub(:render, ->(**) { rendered = true }) do
        result = INTENT.dispatch("play me a sine wave")
        assert result.ok?
        assert_equal :synth_live, result.value[:media]
      end
    end
    assert_equal [:sine, 440.0, INTENT::LIVE_TONE_SECONDS], played
    refute rendered, "a played tone must not also be written to disk"
  end

  def test_a_missing_player_is_named_with_the_fix
    no_player = ->(**) { raise Master::Music::AudioSink::NoPlayerError, "no streaming player found" }
    Master::Music::Realtime.stub(:play, no_player) do
      result = INTENT.dispatch("play a saw wave on my speakers")
      refute result.ok?
      assert_match(/brew install sox/, result.message)
    end
  end

  # "play it" after a render plays that render, whatever else the sentence says.
  def test_play_it_plays_the_last_rendered_file
    played = nil
    INTENT.stub(:last_media, "/home/op/master-sine-20260924T120000Z.wav") do
      Master::Music::Synth.stub(:play, ->(path) { played = path && 4242 }) do
        result = INTENT.dispatch("play it on my sound card")
        assert result.ok?
        assert_equal :playback, result.value[:media]
        assert_match(/pid 4242/, result.value[:output])
      end
    end
    assert_equal 4242, played
  end

  def test_last_media_is_the_newest_render
    Dir.mktmpdir do |dir|
      old = File.join(dir, "master-sine-20260101T000000Z.wav")
      new = File.join(dir, "dilla-20260924T120000Z.mp3")
      File.write(old, "")
      File.write(new, "")
      File.write(File.join(dir, "notes.txt"), "")
      File.utime(Time.now - 60, Time.now - 60, old)
      assert_equal new, INTENT.last_media(dir)
    end
  end

  # The live synthesiser is dilla's: MASTER recognises the sentence and hands
  # it over whole.
  def test_live_synth_sentences_go_to_dilla_live_say
    sentences = ["improvise", "keep playing", "play me something with moog patches", "play a moog bass",
                 "play a lofi pad morphing through dilla_love", "slowly open the filter", "morph to a prophet pad",
                 "play me a chord progression with a few different moog patches", "stop",]
    sentences.each do |sentence|
      sent = nil
      Master::Io::ScriptDispatch.stub(:run, ->(root:, tool:, arg:) { (sent = [tool, arg]) && Master::Result.ok("live0: ok") }) do
        assert INTENT.handles?(sentence), sentence
        assert INTENT.dispatch(sentence).ok?, sentence
      end
      assert_equal ["dilla", "live say #{Shellwords.escape(sentence)}"], sent, sentence
    end
  end

  def test_code_talk_is_not_music
    ["open the patch in the editor", "turn the lead generator into a service", "fix the filter in search",
     "what is a moog",].each do |sentence|
      refute INTENT.live_synth?(sentence), sentence
    end
  end
end
