# frozen_string_literal: true

require "minitest/autorun"

class IdleProfileSpec < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def read(path)
    File.read(File.join(ROOT, path))
  end

  def test_calm_is_default_runtime_profile
    part1 = read("web/public/face.part1.txt")

    assert_includes part1, "['calm', 'full', 'crt', 'battery']"
    assert_includes part1, "function isRichMotionProfile()"
    assert_includes part1, ": 'calm'"
  end

  def test_rich_motion_gates_decorative_idle_features
    part1 = read("web/public/face.part1.txt")
    part3 = read("web/public/face.part3.txt")

    assert_includes part1, "isRichMotionProfile()) startStar()"
    assert_includes part3, "if (!isRichMotionProfile()) return"
    assert_includes part3, "isRichMotionProfile())"
    refute_includes part3, "State.shake = 1.2"
    assert_includes part3, "applyShake(1.2)"
  end
end