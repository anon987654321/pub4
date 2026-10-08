# frozen_string_literal: true

require_relative "test_helper"
require "stringio"

# Enrich adds paralinguistic tags, Playback speaks a reply at a terminal and
# nowhere else, and ProductionDna is the reference table Voice::Dilla reads.
# Nothing here plays audio: the player is looked up on a PATH built for the test
# and never run.
class TestVoiceSupport < Minitest::Test
  PB = Master::Voice::Playback

  def test_enrich_tags_a_later_sentence_when_the_dice_allow
    text = "One. Two. Three."
    Master::Voice::Enrich.stub(:rand, ->(*args) { args.empty? ? 0.0 : 1 }) do
      assert_equal "One. [chuckle] Two. Three.", Master::Voice::Enrich.apply(
        text, { primary: :humor, scores: {} }, tags: true
      )
    end
    Master::Voice::Enrich.stub(:rand, ->(*args) { args.empty? ? 0.99 : 1 }) do
      assert_equal text, Master::Voice::Enrich.apply(
        text, { primary: :humor, scores: {} }, tags: true
      )
    end
  end

  def test_enrich_leaves_single_sentences_and_quiet_comfort_alone
    Master::Voice::Enrich.stub(:rand, ->(*args) { args.empty? ? 0.0 : 1 }) do
      assert_equal "Only one.", Master::Voice::Enrich.apply("Only one.", { primary: :humor }, tags: true)
      assert_equal "A. B.", Master::Voice::Enrich.apply(
        "A. B.", { primary: :comfort, scores: { comfort: 0.1 } }, tags: true
      )
    end
  end

  def test_enrich_is_dry_by_default
    result = Master::Voice::Enrich.apply("One. Two.", { primary: :humor, scores: { humor: 1.0 } })
    refute_includes result, "["
  end

  def with_env(values)
    previous = values.keys.to_h { |key| [key, ENV[key]] }
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def test_playback_speak_now_falls_back_to_native_speech_when_synthesis_is_missing
    spoken = []
    PB.stub(:enabled?, true) do
      PB.stub(:available?, true) do
        PB.stub(:synthesize, nil) do
          PB.stub(:native_say, ->(text) { spoken << text; true }) do
            assert PB.speak_now("hello")
          end
        end
      end
    end

    assert_equal ["hello"], spoken
  end

  def test_playback_background_speech_does_not_repeat_a_failed_reply_through_native_voice
    spoken = []
    queue = Queue.new
    queue << ["hello", "hello", true, :jenny, :warm]
    PB.instance_variable_set(:@queue, queue)
    PB.stub(:native_say, ->(text) { spoken << text; true }) do
      PB.stub(:synthesize, nil) do
        worker = Thread.new { PB.send(:drain) }
        worker.join
      end
    end

    assert_empty spoken
  ensure
    PB.instance_variable_set(:@queue, nil)
  end

  def test_failed_player_exit_is_reported_as_failed_playback
    dir = Dir.mktmpdir("failed-player")
    player_path = File.join(dir, "ffplay")
    audio_path = File.join(dir, "reply.mp3")
    File.write(player_path, "#!/bin/sh\nexit 7\n")
    File.chmod(0o755, player_path)
    File.write(audio_path, "audio")

    PB.remove_instance_variable(:@player) if PB.instance_variable_defined?(:@player)
    with_env("PATH" => dir) do
      PB.stub(:generation_active?, true) do
        refute PB.play(audio_path)
      end
    end
  ensure
    PB.remove_instance_variable(:@player) if PB.instance_variable_defined?(:@player)
    FileUtils.rm_rf(dir)
  end

  def test_failed_preferred_player_falls_through_to_working_player
    dir = Dir.mktmpdir("voice-players")
    bad = File.join(dir, "afplay")
    good = File.join(dir, "ffplay")
    audio = File.join(dir, "reply.mp3")
    File.write(bad, "#!/bin/sh\nexit 7\n")
    File.write(good, "#!/bin/sh\nexit 0\n")
    [bad, good].each { |path| File.chmod(0o755, path) }
    File.write(audio, "audio")

    PB.stub(:player, [bad, []]) do
      PB.stub(:which, ->(cmd) { cmd == "ffplay" ? good : nil }) do
        PB.stub(:generation_active?, true) do
          assert PB.play(audio)
        end
      end
    end
  ensure
    FileUtils.rm_rf(dir)
  end

  def test_player_attempt_failure_falls_back_after_the_player_exits
    dir = Dir.mktmpdir("voice-fallback")
    player = File.join(dir, "ffplay")
    audio = File.join(dir, "reply.mp3")
    File.write(player, "#!/bin/sh\nexit 7\n")
    File.chmod(0o755, player)
    File.write(audio, "audio")
    spoken = []

    PB.stub(:player, [player, []]) do
      PB.stub(:native_say, ->(text) { spoken << text; true }) do
        PB.stub(:generation_active?, true) do
          assert PB.send(:play_or_fallback, audio, "same reply", generation: 0)
        end
      end
    end

    assert_equal ["same reply"], spoken
  ensure
    FileUtils.rm_rf(dir)
  end

  def test_failed_audio_playback_does_not_fall_through_to_native_voice
    spoken = []
    PB.stub(:player, ["/tmp/missing-player", []]) do
      PB.stub(:native_say, ->(text) { spoken << text; true }) do
        PB.stub(:generation_active?, true) do
          refute PB.play("/tmp/missing-audio")
        end
      end
    end

    assert_empty spoken
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
    with_env("PATH" => dir) { assert_equal [File.join(dir, "ffplay"), %w[-nodisp -autoexit -loglevel quiet]], PB.player }
  ensure
    PB.remove_instance_variable(:@player) if PB.instance_variable_defined?(:@player)
    FileUtils.rm_rf(dir)
  end

  def test_speak_refuses_empty_and_keeps_only_the_current_reply
    queued = []
    long = "x" * 12000
    PB.instance_variable_set(:@pending, nil)
    PB.stub(:enabled?, true) do
      PB.stub(:available?, true) do
        PB.stub(:ensure_queue, queued) do
          PB.stub(:start_worker!, nil) do
            PB.speak("   ")
            PB.speak(long)
            PB.speak(" hello ")
          end
        end
      end
    end

    assert_equal 1, queued.size
    assert_equal " hello ".strip, queued.first[1]
    refute_includes queued.map { |job| job[1] }, long
  ensure
    PB.instance_variable_set(:@pending, nil)
    PB.instance_variable_set(:@generation, 0)
  end

  # Two paths reached the door with one reply and MASTER said it twice; a
  # retried synthesis said it a third time. A repeat past the window still
  # speaks, because asking the same question twice is a thing a person does.
  def test_reply_preempts_older_diagnostic_audio
    queued = []
    terminated = false
    PB.instance_variable_set(:@queue, queued)
    PB.instance_variable_set(:@generation, 7)
    PB.instance_variable_set(:@playing_pid, 1234)
    PB.instance_variable_set(:@pending, Set.new)

    PB.stub(:enabled?, true) do
      PB.stub(:available?, true) do
        PB.stub(:ensure_queue, queued) do
          PB.stub(:start_worker!, nil) do
            PB.stub(:terminate_player_locked, -> { terminated = true; PB.instance_variable_set(:@playing_pid, nil) }) do
              PB.speak("new answer")
            end
          end
        end
      end
    end

    assert terminated
    assert_equal 8, PB.instance_variable_get(:@generation)
    assert_equal 1, queued.size
    assert_equal "new answer", queued.first[0]
    assert_equal "new answer", queued.first[1]
    assert_equal true, queued.first[2]
    assert_equal 8, queued.first[7]
  ensure
    PB.instance_variable_set(:@queue, nil)
    PB.instance_variable_set(:@pending, nil)
    PB.instance_variable_set(:@generation, 0)
    PB.instance_variable_set(:@playing_pid, nil)
  end

  def test_a_line_already_waiting_or_just_spoken_is_not_spoken_again
    queued = []
    PB.instance_variable_set(:@pending, nil)
    PB.instance_variable_set(:@last_said, nil)
    PB.instance_variable_set(:@last_at, 0.0)

    PB.stub(:enabled?, true) do
      PB.stub(:available?, true) do
        PB.stub(:ensure_queue, queued) do
          PB.stub(:start_worker!, nil) do
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
    end

    assert_equal ["the same sentence"], queued.map(&:first)
  ensure
    PB.instance_variable_set(:@pending, nil)
    PB.instance_variable_set(:@last_said, nil)
    PB.instance_variable_set(:@generation, 0)
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

  PB.stub(:enabled?, true) do
    PB.stub(:available?, true) do
      PB.stub(:transcendent_mode?, false) do
        PB.stub(:ensure_queue, queued) do
          PB.stub(:start_worker!, nil) { PB.speak(reply) }
        end
      end
    end
  end

  assert_operator queued.size, :>, 1, "the reply went out as one utterance"
  assert_equal reply, queued.map { |job| job[1] }.join(" "), "the words changed on the way out"
  assert_equal [false] * (queued.size - 1) + [true], queued.map(&:last), "only the last utterance closes the reply"
ensure
  PB.instance_variable_set(:@pending, nil)
  PB.instance_variable_set(:@last_said, nil)
end


  def test_transcendent_reply_stays_one_synthesis_unit
    queued = []
    reply = "The melody must stay intact. The phrase contour belongs to one utterance."
    PB.instance_variable_set(:@pending, nil)

    PB.stub(:enabled?, true) do
      PB.stub(:available?, true) do
        PB.stub(:transcendent_mode?, true) do
          PB.stub(:ensure_queue, queued) { PB.stub(:start_worker!, nil) { PB.speak(reply) } }
        end
      end
    end

    assert_equal 1, queued.size
    assert_equal reply, queued.first[1]
    assert_equal true, queued.first[2]
  ensure
    PB.instance_variable_set(:@pending, nil)
  end

  def test_prefetch_returns_prepared_audio_after_background_synthesis
    job = ["second", "second", true, :jenny, :neutral, "+0%", "+0Hz", 0]
    prepared = PB::PreparedAudio.new(
      job:, text: "second", part: "second", last: true, voice: :jenny,
      style: :neutral, rate: "+0%", pitch: "+0Hz", generation: 0,
      path: "/tmp/m_tts_prefetch_test.mp3"
    )

    PB.instance_variable_set(:@generation, 0)
    PB.stub(:prefetch_enabled?, true) do
      PB.stub(:prepare_job, prepared) do
        pending = PB.send(:start_prefetch, job)
        result = PB.send(:await_prefetch, pending)
        assert_same prepared, result
        refute pending.thread.alive?
      end
    end
  end

  def test_prefetch_is_disabled_for_transcendent_mode
    PB.stub(:transcendent_mode?, true) do
      PB.stub(:prefetch_enabled?, false) do
        refute PB.send(:prefetch_enabled?)
      end
    end
  end

  def test_interrupt_clears_queued_speech_and_forgets_last_utterance
    queue = Queue.new
    queue << ["queued", "queued", true, 0]
    PB.instance_variable_set(:@queue, queue)
    PB.instance_variable_set(:@generation, 0)
    PB.instance_variable_set(:@pending, Set.new(["queued"]))
    PB.instance_variable_set(:@last_said, "queued")

    assert PB.interrupt!("voice")
    assert_equal 0, PB.instance_variable_get(:@queue).size
    assert_empty PB.instance_variable_get(:@pending)
    assert_nil PB.instance_variable_get(:@last_said)
    assert_equal 1, PB.instance_variable_get(:@generation)
  ensure
    PB.instance_variable_set(:@queue, nil)
    PB.instance_variable_set(:@pending, nil)
    PB.instance_variable_set(:@last_said, nil)
    PB.instance_variable_set(:@generation, 0)
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
  def test_edge_stream_returns_structured_result_and_byte_count
    audio = StringIO.new
    sock = StringIO.new([5].pack("Q>") + "hello" + [0].pack("Q>"))
    target = Master::Voice::SpeechWorker::StreamTarget.build(io: audio)

    result = Master::Voice::Speech.send(:pump_socket_stream, sock, target)

    assert_instance_of Master::Voice::SpeechWorker::StreamResult, result
    assert result.ok
    assert_equal 5, result.bytes
    assert_equal "hello", audio.string
  end

  def test_edge_stream_marks_eof_after_partial_audio_without_losing_byte_count
    audio = StringIO.new
    sock = StringIO.new([5].pack("Q>") + "he")
    target = Master::Voice::SpeechWorker::StreamTarget.build(io: audio)

    result = Master::Voice::Speech.send(:pump_socket_stream, sock, target)

    refute result.ok
    assert_equal 2, result.bytes
    assert_equal "he", audio.string
  end

  def test_stream_failure_after_audio_never_resynthesizes_the_utterance
    fallback = false
    outcome = PB::StreamOutcome.new(ok: false, played_bytes: 1024)

    PB.stub(:stream_player, ["ffplay", []]) do
      PB.stub(:pump_stream_pipe, outcome) do
        PB.stub(:stream_fallback, ->(_values) { fallback = true; true }) do
          PB.stub(:generation_active?, true) do
            refute PB.send(:stream_utterance, { generation: 0, part: "hello" }, "jenny", {})
          end
        end
      end
    end

    refute fallback, "partially heard speech must never be replayed from the beginning"
  end

  def test_background_playback_falls_back_to_policy_native_voice_when_player_fails
    spoken = []
    job = ["hello", "hello", true, :jenny, :warm]
    delivered = false
    queue = Object.new
    queue.define_singleton_method(:pop) do
      next nil if delivered

      delivered = true
      job
    end

    PB.instance_variable_set(:@queue, queue)
    PB.instance_variable_set(:@generation, 0)
    PB.instance_variable_set(:@job_generations, { job.object_id => 0 })

    PB.stub(:play, false) do
      PB.stub(:native_say, ->(text) { spoken << text; true }) do
        PB.send(:drain)
      end
    end

    assert_equal ["hello"], spoken
  ensure
    PB.instance_variable_set(:@queue, nil)
    PB.instance_variable_set(:@job_generations, {})
    PB.instance_variable_set(:@generation, 0)
  end

end
