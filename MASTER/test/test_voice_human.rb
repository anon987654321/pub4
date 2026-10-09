# frozen_string_literal: true

require_relative "test_helper"

# Text shaping, the human profile, its engine fallback, seeded variation and
# clause streaming order. Nothing here synthesises audio or plays anything.
class TestVoiceHuman < Minitest::Test
  Shaping = Master::Voice::Shaping
  Policy = Master::Voice::Policy

  def setup
    @profile = ENV.delete("MASTER_TTS_PROFILE")
    Policy.reload!
  end

  def teardown
    @profile ? ENV["MASTER_TTS_PROFILE"] = @profile : ENV.delete("MASTER_TTS_PROFILE")
    Policy.reload!
  end

  def with_profile(name)
    ENV["MASTER_TTS_PROFILE"] = name
    Policy.reload!
    yield
  ensure
    ENV.delete("MASTER_TTS_PROFILE")
    Policy.reload!
  end

  # ---- speakable text --------------------------------------------------------

  def test_a_count_is_spoken_as_a_count_not_a_date
    assert_equal "12 of 12", Shaping.speakable("12/12", lang: :en).strip
    assert_equal "7 of 9", Shaping.speakable("7/9", lang: :en).strip
    assert_equal "Tests passed 12 of 12 today", Shaping.speakable("Tests passed 12/12 today", lang: :en).strip
  end

  def test_a_count_in_norwegian_uses_av
    assert_equal "12 av 12", Shaping.speakable("12/12", lang: :nb).strip
    assert_equal "Alle 12 av 12 tester er ferdige", Shaping.speakable("Alle 12/12 tester er ferdige").strip
  end

  def test_real_dates_and_decimals_are_left_to_the_engine
    ["12/12/2026", "1.2/3", "12.10.2026", "3/12/2026 and 5"].each do |text|
      assert_equal text, Shaping.speakable(text, lang: :en).strip, text
    end
    refute_match(/ of /, Shaping.speakable("on 12/12/2026", lang: :en))
  end

  def test_and_or_and_plain_words_around_slashes_survive
    assert_equal "and/or", Shaping.speakable("and/or", lang: :en).strip
    assert_equal "read/write", Shaping.speakable("read/write", lang: :en).strip
  end

  def test_hashes_become_a_commit
    assert_equal "Fixed in a commit now", Shaping.speakable("Fixed in 694da5d1e now", lang: :en).strip
    assert_equal "Rettet i en commit", Shaping.speakable("Rettet i 694da5d1e", lang: :nb).strip
    assert_equal "call 12345678", Shaping.speakable("call 12345678", lang: :en).strip, "digits only is a number"
    assert_equal "a defaced page", Shaping.speakable("a defaced page", lang: :en).strip, "letters only is a word"
  end

  def test_paths_are_spoken_by_their_last_part
    assert_equal "Open speech dot rb", Shaping.speakable("Open MASTER/lib/voice/speech.rb", lang: :en).strip
    assert_equal "in voice", Shaping.speakable("in /usr/local/voice", lang: :en).strip
    assert_equal "Åpne speech punkt rb", Shaping.speakable("Åpne lib/voice/speech.rb").strip
  end

  def test_urls_are_spoken_as_the_host
    assert_equal "See example.com now", Shaping.speakable("See https://www.example.com/a/b?x=1 now", lang: :en).strip
  end

  def test_versions_and_units
    assert_equal "version 1 point 2 point 3", Shaping.speakable("v1.2.3", lang: :en).strip
    assert_equal "versjon 1 komma 2 komma 3", Shaping.speakable("v1.2.3", lang: :nb).strip
    assert_equal "took 340 milliseconds", Shaping.speakable("took 340ms", lang: :en).strip
    assert_equal "1 second and 12 percent", Shaping.speakable("1s and 12%", lang: :en).strip
    assert_equal "12 prosent", Shaping.speakable("12%", lang: :nb).strip
    assert_equal "5 minutes", Shaping.speakable("5 minutes", lang: :en).strip, "a word that starts with a unit letter stays"
  end

  def test_abbreviations
    assert_equal "for example this", Shaping.speakable("e.g. this", lang: :en).strip
    assert_equal "one, two, et cetera. Next", Shaping.speakable("one, two, etc. Next", lang: :en).strip
    assert_equal "for eksempel dette", Shaping.speakable("f.eks. dette").strip
  end

  def test_markdown_is_stripped
    text = "# Title\n\n- **bold** and `code`\n- [link](http://x.y/z)\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n```ruby\nputs 1\n```\nEnd."
    spoken = Shaping.speakable(text, lang: :en)
    refute_match(/[#*`|\[\]]|puts|---/, spoken)
    assert_includes spoken, "Title."
    assert_includes spoken, "bold and code."
    assert_includes spoken, "link."
    assert_includes spoken, "a, b."
    assert_includes spoken, "End."
  end

  def test_norwegian_prose_is_not_mangled
    text = "Vi må ikke endre æøå, og det går bra."
    assert_equal text, Shaping.speakable(text).strip
  end

  def test_clean_text_applies_the_shaping_for_every_voice
    assert_includes Master::Voice::Speech.clean_text("Tests passed 12/12"), "12 of 12"
  end

  # ---- the clause plan and variation ----------------------------------------

  LONG = "This is a rather long sentence that keeps going, and then it continues with more words " \
         "because we need a clause split here. Short one?\n\nNew paragraph starts here."

  def test_long_sentences_split_at_clause_boundaries
    clauses = Shaping.plan(LONG, lang: :en, seed: 1)
    assert_operator clauses.size, :>=, 4
    assert clauses.all? { |c| c.text.length <= 130 }, clauses.map(&:text).inspect
    assert_equal "This is a rather long sentence that keeps going,", clauses.first.text
  end

  def test_pauses_follow_punctuation_and_paragraphs
    pauses = Shaping.settings
    clauses = Shaping.plan(LONG, lang: :en, seed: 1)
    assert_equal pauses["comma_ms"], clauses[0].pause_ms
    assert_equal pauses["period_ms"], clauses[1].pause_ms
    assert_equal pauses["paragraph_ms"], clauses[2].pause_ms, "after the paragraph's last sentence"
    assert_operator clauses[2].pause_ms, :>, clauses[1].pause_ms
    assert_equal 0, clauses.last.pause_ms
  end

  def test_a_long_sentence_gets_a_breath_and_a_short_one_does_not
    clauses = Shaping.plan(LONG, lang: :en, seed: 1)
    assert clauses.first.breath
    refute clauses.drop(1).any?(&:breath)
  end

  def test_variation_is_off_for_the_default_voice
    clauses = Shaping.plan(LONG, lang: :en, seed: 1, base_rate: "-5%", base_pitch: "-12Hz")
    assert_equal ["-5%"], clauses.map(&:rate).uniq
    assert_equal ["-12Hz"], clauses.map(&:pitch).uniq
  end

  def test_variation_is_deterministic_per_seed_and_bounded
    with_profile("human") do
      a = Shaping.plan(LONG, lang: :en, seed: 7, base_rate: "-4%", base_pitch: "-8Hz").map { |c| [c.rate, c.pitch] }
      b = Shaping.plan(LONG, lang: :en, seed: 7, base_rate: "-4%", base_pitch: "-8Hz").map { |c| [c.rate, c.pitch] }
      c = Shaping.plan(LONG, lang: :en, seed: 8, base_rate: "-4%", base_pitch: "-8Hz").map { |x| [x.rate, x.pitch] }
      assert_equal a, b
      refute_equal a, c
      cfg = Shaping.variation_settings
      limit_rate = cfg["rate_jitter_pct"] + cfg["end_slow_pct"].abs
      limit_pitch = cfg["pitch_jitter_hz"] + [cfg["end_fall_hz"].abs, cfg["question_rise_hz"].abs].max
      a.each do |rate, pitch|
        assert_operator (rate.to_i + 4).abs, :<=, limit_rate
        assert_operator (pitch.to_i + 8).abs, :<=, limit_pitch
      end
    end
  end

  def test_a_statement_end_falls_and_a_question_rises
    with_profile("human") do
      clauses = Shaping.plan("It is done. Is it done?", lang: :en, seed: 3, base_rate: "+0%", base_pitch: "+0Hz")
      assert_operator clauses[0].pitch.to_i, :<, 0
      assert_operator clauses[1].pitch.to_i, :>, 0
    end
  end

  # ---- the profile and the engine fallback ----------------------------------

  def test_the_default_voice_is_edge_and_not_the_human_pipeline
    refute Policy.human_pipeline?
    refute Master::Voice::Human.active?
  end

  def test_the_human_profile_turns_the_pipeline_on_and_names_its_engines
    with_profile("human") do
      assert Policy.human_pipeline?
      assert Master::Voice::Human.active?
      assert_equal "human", Policy.profile_name
      refute_empty Master::Voice::LocalTts.entries
      assert Policy.breath
    end
  end

  def test_the_human_chain_is_lighter_than_the_default
    default = Policy.post_chain
    with_profile("human") do
      human = Policy.post_chain
      refute_equal default, human
      refute_includes human, "acompressor"
      assert_operator human.split(",").size, :<, default.split(",").size
    end
  end

  def test_a_missing_engine_binary_is_unavailable_and_never_raises
    entry = { "bin" => "/nonexistent/mlx_audio.tts.generate", "model" => "m" }
    with_env("MASTER_LOCAL_TTS_BIN" => nil, "PATH" => "/nonexistent") do
      Dir.stub(:home, "/nonexistent") do
        refute Master::Voice::LocalTts.available?(entry)
        refute Master::Voice::LocalTts.synthesize(entry, "hello", "/tmp/m_tts_never.wav")
      end
    end
  end

  def test_the_chain_falls_through_to_edge_when_the_local_engine_is_missing
    with_profile("human") do
      clause = Shaping::Clause.new(text: "Hello there.", pause_ms: 0, rate: "+0%", pitch: "+0Hz")
      edge = []
      Master::Voice::LocalTts.stub(:available?, false) do
        Master::Voice::Human.stub(:edge_audio, ->(c, _v) { edge << c.text; nil }) do
          assert_nil Master::Voice::Human.engine_audio(clause, :en, nil)
        end
      end
      assert_equal ["Hello there."], edge, "edge must be tried after the local engines"
    end
  end

  def test_a_failing_local_engine_falls_through_without_raising
    with_profile("human") do
      clause = Shaping.plan("Hello there.", lang: :en, seed: 1).first
      Master::Voice::LocalTts.stub(:available?, true) do
        Master::Voice::LocalTts.stub(:synthesize, false) do
          Master::Voice::Human.stub(:edge_audio, "/tmp/m_tts_edge_stub.mp3") do
            assert_equal "/tmp/m_tts_edge_stub.mp3", Master::Voice::Human.engine_audio(clause, :en, nil)
          end
        end
      end
    end
  end

  def test_the_cli_binary_is_never_an_mlx_engine_for_chatterbox_models
    cfg = { "mlx_model" => "mlx-community/chatterbox-fp16" }
    Master::Voice::Engines.stub(:mlx_python, "python3") do
      Master::Io::Exec.stub(:capture2, ["", Struct.new(:success?).new(false)]) do
        refute Master::Voice::Engines.mlx_cli?(cfg), "the CLI cannot run chatterbox; only the python API can"
      end
    end
  end

  def test_default_edge_path_is_untouched_by_the_human_hook
    refute Master::Voice::Human.active?
    Master::Voice::Human.stub(:synthesize, ->(*) { flunk "human pipeline ran for the default voice" }) do
      Master::Voice::Speech.stub(:available?, false) do
        assert_nil Master::Voice::Speech.synthesize("Hello", mode: "classic")
      end
    end
  end

  # ---- streaming order -------------------------------------------------------

  MESSAGE = "I looked at the failing job and the cause is in the retry handler, which swallows the timeout. " \
            "The fix is small, but it touches the queue, so I want the tests to run twice before we ship it. " \
            "After that, the deploy is a single command, and nothing else needs to change on the box."

  def test_the_first_packet_is_a_short_clause_and_the_order_is_kept
    chunks = Master::Voice::Speech.chunks(MESSAGE)
    limit = Policy.first_chunk_chars
    assert_operator MESSAGE.length, :>, 250
    assert_operator chunks.first.length, :<=, limit + 5
    assert_equal Master::Voice::Speech.clean_text(MESSAGE).gsub(/\s+/, " ").gsub(/\.+/, "."), chunks.join(" ").gsub(/\s+/, " "),
                 "no word may be lost or reordered by the cut"
  end

  def test_the_first_packet_cut_can_be_turned_off
    Policy.stub(:first_chunk_chars, 0) do
      assert_operator Master::Voice::Speech.chunks(MESSAGE).first.length, :>, 100
    end
  end

  def test_human_clause_jobs_keep_order_and_mark_only_the_last
    with_profile("human") do
      jobs = Master::Voice::Playback.human_jobs(LONG, :jenny, :warm, 1)
      assert_equal Shaping.plan(LONG, seed: nil).map(&:text), jobs.map { |j| j[:text] }
      assert_equal [false] * (jobs.size - 1) + [true], jobs.map { |j| j[:last] }
      assert jobs.all? { |j| j.key?(:pause_ms) && j[:generation] == 1 }
    end
  end

  def test_the_worker_plays_queued_clauses_in_order_without_overlap
    playback = Master::Voice::Playback
    played = []
    active = 0
    overlap = false
    queue = Queue.new
    playback.instance_variable_set(:@queue, queue)
    jobs = %w[one two three four].map { |t| { text: t, last: t == "four", generation: playback.current_generation } }
    jobs.drop(1).each { |j| queue << j }
    prepare = ->(job, live: true) { Struct.new(:text, :path, :generation).new(job[:text], nil, job[:generation]) }
    consume = lambda do |prepared|
      active += 1
      overlap ||= active > 1
      sleep 0.01
      played << prepared.text
      active -= 1
      true
    end
    ENV["MASTER_TTS_PREFETCH"] = "0"
    playback.stub(:prepare_job, prepare) do
      playback.stub(:consume_prepared, consume) do
        playback.stub(:cleanup_prepared, nil) do
          playback.process_job_sequence(jobs.first)
        end
      end
    end
    assert_equal %w[one two three four], played
    refute overlap
  ensure
    ENV.delete("MASTER_TTS_PREFETCH")
    playback.instance_variable_set(:@queue, nil)
  end

  private

  def with_env(vars)
    saved = vars.keys.to_h { |k| [k, ENV[k]] }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end
