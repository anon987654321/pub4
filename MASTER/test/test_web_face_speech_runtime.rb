# frozen_string_literal: true

require "minitest/autorun"
require "digest"

class FaceSpeechRuntimeSpec < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def read(path)
    File.read(File.join(ROOT, path))
  end

  def test_speech_runtime_is_separate_module
    speech = read("../RAILS/master/public/face_speech_runtime.js")
    rake = read("../RAILS/master/lib/tasks/face_runtime.rake")

    assert_includes speech, "function enqueueSpeech"
    assert_includes speech, "function ttsTick"
    assert_includes speech, "function loadTTSBlob"
    assert_includes rake, "face_speech_runtime.js"
  end

  # face.part4.txt was a 96-byte "moved to face_speech_runtime.js" stub that the
  # build task never read. This used to assert the stub did not contain the TTS
  # implementation, which is true of any file that does not exist; what actually
  # matters is that the build task's segment list and the files on disk agree.
  def test_generated_runtime_carries_current_tts_guards
    source = read("../RAILS/master/public/face_speech_runtime.js")
    bundle = read("../RAILS/master/public/face.runtime.js")

    # The browser speechSynthesis fallback (and its female-voice regex) is gone; every utterance is server TTS.
    refute_includes source, "speechSynthesis"
    assert_includes source, "Do not play a truncated MP3"

    # face.runtime.js is a content-addressed loader, not an inline copy of the
    # sources. Its manifest must point at the current speech module digest.
    path = File.join(ROOT, "../RAILS/master/public/face_speech_runtime.js")
    digest = Digest::SHA256.file(path).hexdigest[0, 10]
    assert_includes bundle, "face_speech_runtime.js?v=#{digest}"
    refute_includes source, "const audioStream = window.MASTER_RUNTIME?.enhancements?.includes?.('tts_audio_stream')"
    refute_includes source, "let browserFallbackTimer = setTimeout"
    refute_includes source, "if (pending.length <= TTS_CHUNK_MAX)"
  end

  def test_retired_partial_tts_path_is_absent
    source = read("../RAILS/master/public/face_speech_runtime.js")
    bundle = read("../RAILS/master/public/face.runtime.js")
    runtime = read("data/runtime.yml")

    refute_includes source, "function tryPartialTTSPlay"
    refute_includes source, "function tryPartialTTSPlay"
    refute_includes runtime, "tts_audio_stream"
    refute_includes runtime, "enh_tts_audio_stream"
  end

  def test_council_speech_never_bypasses_the_serial_tts_queue
    source = read("../RAILS/master/public/face.part5.txt")
    bundle = read("../RAILS/master/public/face.runtime.js")

    expected = "enqueueSpeech(text, { quirky: false });"
    assert_includes source, expected
    assert_includes source, expected
    refute_includes source, "playDuo([[guardVoice(voice), text]]"
    refute_includes source, "playDuo([[guardVoice(voice), text]]"
  end

  def test_no_face_part_exists_outside_the_build_manifest
    rake = read("../RAILS/master/lib/tasks/face_runtime.rake")
    # The task names parts two ways: a range it maps over, and explicit
    # face.partN.txt literals for the tail.
    ranged = rake.scan(/\((\d+)\.\.(\d+)\)\.map/).flat_map { |low, high| (low.to_i..high.to_i).to_a }
    literal = rake.scan(/face\.part(\d+)\.txt/).flatten.map(&:to_i)
    built = (ranged + literal).uniq.sort

    on_disk = Dir.glob(File.join(ROOT, "../RAILS/master/public/face.part*.txt"))
                 .map { |path| File.basename(path)[/face\.part(\d+)\.txt/, 1].to_i }.sort

    refute_empty built
    assert_equal built, on_disk,
                 "face.part*.txt on disk and the assets:build_face_runtime segment list disagree"
  end
  def test_voice_preview_uses_the_single_tts_playback_path
    source = read("../RAILS/master/public/face.part5.txt")

    assert_includes source, "function previewVoice(voice)"
    assert_includes source, 'enqueueSpeech("Let\'s work now.", { quirky: false });'
    refute_includes source, "const audio = new Audio(src);"
    refute_includes source, "audio.playbackRate = getTtsRate();"
    refute_includes source, 'playDuo([[chosen, "Let\'s work now."]'
  end

  def test_live_stream_tts_does_not_replay_already_spoken_text
    source = read("../RAILS/master/public/face.part1.txt")
    consumer = read("../RAILS/master/public/face.part5.txt")
    bundle = read("../RAILS/master/public/face.runtime.js")

    assert_includes source, "const alreadySpoken = Math.max(0, Math.min(text.length, Number(opts.spokenLen) || 0));"
    assert_includes source, "let rest = text.slice(alreadySpoken).trimStart();"
    # part5 streams the reply and passes how much it already spoke; part1 skips that much.
    assert_includes consumer, "spokenLen: ttsStreamSpokenLen"
  end
end
