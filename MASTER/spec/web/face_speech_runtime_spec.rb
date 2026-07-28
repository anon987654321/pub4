# frozen_string_literal: true

require "minitest/autorun"

class FaceSpeechRuntimeSpec < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def read(path)
    File.read(File.join(ROOT, path))
  end

  def test_speech_runtime_is_separate_module
    speech = read("web/public/face_speech_runtime.js")
    rake = read("web/lib/tasks/face_runtime.rake")

    assert_includes speech, "function enqueueSpeech"
    assert_includes speech, "function ttsTick"
    assert_includes speech, "function loadTTSBlob"
    assert_includes rake, "face_speech_runtime.js"
  end

  # face.part4.txt was a 96-byte "moved to face_speech_runtime.js" stub that the
  # build task never read. This used to assert the stub did not contain the TTS
  # implementation, which is true of any file that does not exist; what actually
  # matters is that the build task's segment list and the files on disk agree.
  def test_no_face_part_exists_outside_the_build_manifest
    rake = read("web/lib/tasks/face_runtime.rake")
    # The task names parts two ways: a range it maps over, and explicit
    # face.partN.txt literals for the tail.
    ranged = rake.scan(/\((\d+)\.\.(\d+)\)\.map/).flat_map { |low, high| (low.to_i..high.to_i).to_a }
    literal = rake.scan(/face\.part(\d+)\.txt/).flatten.map(&:to_i)
    built = (ranged + literal).uniq.sort

    on_disk = Dir.glob(File.join(ROOT, "web/public/face.part*.txt"))
                 .map { |path| File.basename(path)[/face\.part(\d+)\.txt/, 1].to_i }.sort

    refute_empty built
    assert_equal built, on_disk,
                 "face.part*.txt on disk and the assets:build_face_runtime segment list disagree"
  end
end
