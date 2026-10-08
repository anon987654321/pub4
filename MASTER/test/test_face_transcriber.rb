# frozen_string_literal: true

require_relative "test_helper"

# The ear transcribes with whisper.cpp where it is installed, with Gemini only
# where it is not, and with nothing rather than a guess. A free Gemini key
# allows twenty requests a day and live words want one a second.
class TestFaceTranscriber < Minitest::Test
  Transcriber = Master::CLI::Face::Transcriber
  Ok = Struct.new(:success?)

  def setup
    @dir = Dir.mktmpdir
    @model = File.join(@dir, "ggml-small.bin")
    File.open(@model, "wb") { |f| f.truncate(Transcriber::MIN_MODEL_BYTES) }
    @calls = []
  end

  def teardown = FileUtils.rm_rf(@dir)

  def transcriber(whisper: true, key: nil, model: @model, out: " [BLANK_AUDIO]\n Hei, verden.\n")
    Transcriber.new(env: { "MASTER_WHISPER_MODEL" => model }, which: ->(cmd) { whisper && cmd == "whisper-cli" },
                    run: ->(*argv) { @calls << argv; [out, "", Ok.new(true)] }, gemini_key: -> { key })
  end

  def test_whisper_comes_first
    assert_equal :whisper, transcriber(key: "k").lane
  end

  def test_gemini_answers_only_without_whisper
    assert_equal :gemini, transcriber(whisper: false, key: "k").lane
    assert_equal :gemini, transcriber(key: "k", model: File.join(@dir, "absent.bin")).lane
  end

  def test_nothing_transcribes_without_either
    words = transcriber(whisper: false)
    assert_nil words.lane
    assert_nil words.final("\0" * 32_000)
    assert_match(/no whisper-cli/, words.describe)
  end

  def test_a_download_cut_short_is_no_model
    File.open(@model, "wb") { |f| f.truncate(1_000) }
    assert_nil transcriber.model
  end

  def test_whisper_hears_both_languages_and_drops_its_silence_marks
    assert_equal "Hei, verden.", transcriber.final("\0" * 32_000)
    argv = @calls.last
    assert_equal ["whisper-cli", "-m", @model], argv.first(3)
    assert_equal %w[-nt -np -l auto], argv.last(4)
  end

  def test_interims_take_the_fast_model_beside_the_accurate_one
    base = File.join(@dir, "ggml-base.bin")
    words = transcriber
    assert_equal @model, words.interim_model
    File.open(base, "wb") { |f| f.truncate(Transcriber::MIN_MODEL_BYTES) }
    words.interim("\0" * 32_000)
    assert_equal base, @calls.last[2]
  end

  def test_the_wav_is_what_whisper_reads
    wav = nil
    words = Transcriber.new(env: { "MASTER_WHISPER_MODEL" => @model }, which: ->(_) { true }, gemini_key: -> {},
                            run: ->(*argv) { wav = File.binread(argv[4]); ["x", "", Ok.new(true)] })
    words.final("\1\0" * 100)
    assert_equal "RIFF", wav[0, 4]
    assert_equal 16_000, wav[24, 4].unpack1("V")
    assert_equal 244, wav.bytesize
  end
end
