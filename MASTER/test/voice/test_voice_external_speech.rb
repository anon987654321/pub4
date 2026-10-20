# frozen_string_literal: true

require_relative "../test_helper"

class TestVoiceExternalSpeech < Minitest::Test
  Playback = Master::Voice::Playback
  Narrator = Master::Voice::Narrator

  def test_the_speaker_is_held_while_another_mouth_speaks_and_free_after
    refute_predicate Playback, :external_speaking?

    Playback.external_speech { assert_predicate Playback, :external_speaking? }

    refute_predicate Playback, :external_speaking?
  end

  def test_a_mouth_that_raises_still_gives_the_speaker_back
    assert_raises(RuntimeError) { Playback.external_speech { raise "mouth died" } }

    refute_predicate Playback, :external_speaking?
  end

  def test_the_queue_waits_for_the_other_mouth_but_only_up_to_its_limit
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Playback.external_speech { Playback.wait_for_external_speech(limit_s: 0.3) }

    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :>=, 0.25
  end

  def test_the_bard_holds_its_tongue_while_the_face_speaks
    bard = Narrator.new(voice: :bard, backlog: -> { 0 }, audible: -> { true }, speaker: ->(_line) { true })

    Playback.external_speech { assert_equal :held, bard.tick }
  end
end

class TestFaceMouthHoldsTheSpeaker < Minitest::Test
  def test_the_mouth_holds_the_speaker_while_it_says_a_reply
    mouth = Master::CLI::Face::Mouth.new(synthesize: ->(_text) { nil })
    held = nil
    mouth.stub(:available?, false) do
      Master::Voice::Playback.stub(:external_speech, ->(&block) { held = true; block.call }) do
        mouth.say("hello", on_level: ->(_level) {})
      end
    end

    assert held
  end
end
