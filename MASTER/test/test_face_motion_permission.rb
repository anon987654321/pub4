# frozen_string_literal: true

require_relative "test_helper"

# iOS 13+ splits DeviceOrientationEvent and DeviceMotionEvent permissions.
# requestMotionPermission used to ask only for orientation, then listen for
# motion immediately at parse time — shake-to-skip never fired on an iPhone.
class TestFaceMotionPermission < Minitest::Test
  def part3
    File.read(File.join(Master::ROOT, "web/public/face.part3.txt"))
  end

  def test_asks_for_motion_as_well_as_orientation
    source = part3
    assert_includes source, "requestSensorPermission(window.DeviceMotionEvent"
    assert_includes source, "requestSensorPermission(window.DeviceOrientationEvent"
    assert_includes source, "Ctor.requestPermission"
    assert_includes source, "bindMotion"
  end

  def test_does_not_bind_motion_before_the_primer_grant
    source = part3
    bind_at = source.index("function bindMotion")
    request_at = source.index("async function requestMotionPermission")
    refute_nil bind_at
    refute_nil request_at
    assert_operator request_at, :>, bind_at
    refute_match(/if \(window\.DeviceMotionEvent\) \{\s*window\.addEventListener\('devicemotion'/, source)
  end
end
