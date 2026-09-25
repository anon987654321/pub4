# frozen_string_literal: true

require_relative "test_helper"

# Enrich adds paralinguistic tags, Playback speaks a reply at a terminal and
# nowhere else, and ProductionDna is the reference table Voice::Dilla reads.
# Nothing here plays audio: the player is looked up on a PATH built for the test
# and never run.
class TestVoiceSupport < Minitest::Test
  PB = Master::Voice::Playback

  def test_enrich_tags_a_later_sentence_when_the_dice_allow
    text = "One. Two. Three."
    Master::Voice::Enrich.stub(:rand, ->(*args) { args.empty? ? 0.0 : 1 }) do
      assert_equal "One. [chuckle] Two. Three.", Master::Voice::Enrich.apply(text, { primary: :humor, scores: {} })
    end
    Master::Voice::Enrich.stub(:rand, ->(*args) { args.empty? ? 0.99 : 1 }) do
      assert_equal text, Master::Voice::Enrich.apply(text, { primary: :humor, scores: {} })
    end
  end

  def test_enrich_leaves_single_sentences_and_quiet_comfort_alone
    Master::Voice::Enrich.stub(:rand, ->(*args) { args.empty? ? 0.0 : 1 }) do
      assert_equal "Only one.", Master::Voice::Enrich.apply("Only one.", { primary: :humor })
      assert_equal "A. B.", Master::Voice::Enrich.apply("A. B.", { primary: :comfort, scores: { comfort: 0.1 } })
    end
  end

  def with_env(values)
    previous = values.keys.to_h { |key| [key, ENV[key]] }
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def test_playback_is_silent_off_a_terminal_and_when_told_to_be
    $stdout.stub(:isatty, true) do
      with_env("MASTER_CLI_SPEAK" => nil, "MASTER_SKIP_TTS" => nil, "CI" => nil) { assert PB.enabled? }
      with_env("MASTER_CLI_SPEAK" => "0", "MASTER_SKIP_TTS" => nil, "CI" => nil) { refute PB.enabled? }
      with_env("MASTER_CLI_SPEAK" => nil, "MASTER_SKIP_TTS" => nil, "CI" => "1") { refute PB.enabled? }
    end
    $stdout.stub(:isatty, false) do
      with_env("MASTER_CLI_SPEAK" => nil, "MASTER_SKIP_TTS" => nil, "CI" => nil) { refute PB.enabled? }
    end
  end

  def test_the_first_player_on_path_wins_in_preference_order
    dir = Dir.mktmpdir("players_")
    %w[mpv ffplay].each do |name|
      File.write(File.join(dir, name), "#!/bin/sh\n")
      File.chmod(0o755, File.join(dir, name))
    end
    PB.remove_instance_variable(:@player) if PB.instance_variable_defined?(:@player)
    with_env("PATH" => dir) { assert_equal ["ffplay", %w[-nodisp -autoexit -loglevel quiet]], PB.player }
  ensure
    PB.remove_instance_variable(:@player) if PB.instance_variable_defined?(:@player)
    FileUtils.rm_rf(dir)
  end

  def test_speak_refuses_empty_and_document_length_text_before_anything_else
    queued = []
    PB.stub(:enabled?, true) do
      PB.stub(:available?, true) do
        PB.stub(:ensure_worker, queued) do
          PB.speak("   ")
          PB.speak("x" * 12000)
          PB.speak(" hello ")
        end
      end
    end

    assert_equal ["hello"], queued.map { |job| job[1] }
  end

  # Two paths reached the door with one reply and MASTER said it twice; a
  # retried synthesis said it a third time. A repeat past the window still
  # speaks, because asking the same question twice is a thing a person does.
  def test_a_line_already_waiting_or_just_spoken_is_not_spoken_again
    queued = []
    PB.instance_variable_set(:@pending, nil)
    PB.instance_variable_set(:@last_said, nil)
    PB.instance_variable_set(:@last_at, 0.0)

    PB.stub(:enabled?, true) do
      PB.stub(:available?, true) do
        PB.stub(:ensure_worker, queued) do
          PB.speak("the same sentence")
          PB.speak("the same sentence")
          PB.send(:spoken, "the same sentence")
          PB.speak("the same sentence")
          PB.speak("a different sentence")
          PB.instance_variable_set(:@last_at, Process.clock_gettime(Process::CLOCK_MONOTONIC) - PB::ECHO_WINDOW_S - 1)
          PB.speak("the same sentence")
        end
      end
    end

    assert_equal ["the same sentence", "a different sentence", "the same sentence"], queued.map(&:first)
  ensure
    PB.instance_variable_set(:@pending, nil)
    PB.instance_variable_set(:@last_said, nil)
  end

# One Edge round trip carried the whole reply, so a long answer stood silent
# for its entire synthesis and then spoke. Speech.chunks packed sentences and
# had no caller.
def test_a_reply_is_spoken_sentence_by_sentence_so_the_first_words_come_first
  queued = []
  reply = "The pool is every model this machine can reach. A lane joins it when it can answer. " \
          "A model outside it carries the one thing to do about that. " \
          "The council argues inside the loop, and its picks ride into the repair as context."
  PB.instance_variable_set(:@pending, nil)
  PB.instance_variable_set(:@last_said, nil)

  PB.stub(:enabled?, true) { PB.stub(:available?, true) { PB.stub(:ensure_worker, queued) { PB.speak(reply) } } }

  assert_operator queued.size, :>, 1, "the reply went out as one utterance"
  assert_equal reply, queued.map { |job| job[1] }.join(" "), "the words changed on the way out"
  assert_equal [false] * (queued.size - 1) + [true], queued.map(&:last), "only the last utterance closes the reply"
ensure
  PB.instance_variable_set(:@pending, nil)
  PB.instance_variable_set(:@last_said, nil)
end

  DNA = Master::Voice::ProductionDna

  def test_the_dna_brief_restates_the_dilla_table
    dilla = DNA.producer("j_dilla")
    timing = dilla[:timing]

    assert_includes DNA.brief, "#{timing[:ppqn]} PPQN"
    assert_includes DNA.brief, "#{timing[:swing_percent].min}-#{timing[:swing_percent].max}% swing"
    assert_includes DNA.brief, "#{timing[:bpm].min}-#{timing[:bpm].max} BPM"
  end

  def test_every_numbered_progression_has_one_numeral_per_chord
    DNA::CHORDS.each_value do |collections|
      collections.each_value do |tracks|
        tracks.each do |track|
          next unless track[:roman]

          assert_equal track[:chords].size, track[:roman].size, track[:track]
        end
      end
    end
  end

  def test_unknown_names_raise_rather_than_reading_nil
    assert_raises(KeyError) { DNA.producer(:nobody) }
    assert_raises(KeyError) { DNA.chords_for(:j_dilla, :not_an_album) }
    assert_kind_of Hash, DNA.preset(:dilla_drum_bus)
  end
end
