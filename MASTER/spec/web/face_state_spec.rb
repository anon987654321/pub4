# frozen_string_literal: true

require "minitest/autorun"

class FaceStateSpec < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def read(path)
    File.read(File.join(ROOT, path))
  end

  def test_layout_loads_face_state_before_visual_scripts
    source = read("web/app/views/layouts/application.html.erb")
    assert_includes source, "/face_state.js"
    assert_operator source.index("/face_state.js"), :<, source.index("/visual_governor.js")
    assert_includes source, "data-master-state=\"idle\""
  end

  def test_face_state_classifies_runtime_status
    source = read("web/public/face_state.js")
    assert_includes source, "data.masterState"
    assert_includes source, "Show process status"
    assert_includes source, 'input.value = "/process"'
  end

  def test_visual_governor_is_quiet_and_freezes_on_fail
    source = read("web/public/visual_governor.js")
    assert_includes source, "const maxFps = 18"
    assert_includes source, "const maxParticles = 96"
    assert_includes source, "freezeOnFail: true"
    assert_includes source, "dataset.masterState === \"fail\""
  end
end
