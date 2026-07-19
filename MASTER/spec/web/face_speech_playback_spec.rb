# frozen_string_literal: true

require "minitest/autorun"

class FaceSpeechPlaybackSpec < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def read(path)
    File.read(File.join(ROOT, path))
  end

  def test_playback_module_holds_viseme_functions
    playback = read("web/public/face_speech_playback.js")
    speech = read("web/public/face_speech_runtime.js")
    part5 = read("web/public/face.part5.txt")
    rake = read("web/lib/tasks/face_runtime.rake")

    assert_includes playback, "function startVisemeAnim"
    assert_includes playback, "function stopVisemeAnim"
    assert_includes playback, "function setViseme"
    assert_includes playback, "MASTER_SPEECH_PLAYBACK"
    assert_includes rake, "face_speech_playback.js"
    refute_includes speech, "function setViseme"
    refute_includes part5, "function startVisemeAnim"
  end
end
