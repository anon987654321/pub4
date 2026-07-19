# frozen_string_literal: true

require "minitest/autorun"

class FaceSpeechRuntimeSpec < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def read(path)
    File.read(File.join(ROOT, path))
  end

  def test_speech_runtime_is_separate_module
    speech = read("web/public/face_speech_runtime.js")
    stub = read("web/public/face.part4.txt")
    rake = read("web/lib/tasks/face_runtime.rake")

    assert_includes speech, "function enqueueSpeech"
    assert_includes speech, "function ttsTick"
    assert_includes speech, "function loadTTSBlob"
    assert_includes stub, "face_speech_runtime.js"
    assert_includes rake, "face_speech_runtime.js"
  end

  def test_part4_stub_no_longer_holds_tts_implementation
    stub = read("web/public/face.part4.txt")

    refute_includes stub, "function enqueueSpeech"
    refute_includes stub, "const tts ="
  end
end
