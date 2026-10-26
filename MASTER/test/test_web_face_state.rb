# frozen_string_literal: true

require "minitest/autorun"
require_relative "support_face_manifest_helper"

class FaceStateSpec < Minitest::Test
  include FaceManifestHelper

  ROOT = File.expand_path("..", __dir__)

  def read(path)
    File.read(File.join(ROOT, path))
  end

  # layouts/application.html.erb is not the real boot page — ChatController#index
  # renders with `layout: false` (see web/CLAUDE.md), so chat/index.html.erb is
  # the single actual HTML entrypoint. face_state/visual_governor load there via
  # a Rails javascript_include_tag array, not literal <script src> tags.
  def test_layout_loads_face_state_before_visual_scripts
    scripts = shell_manifest
    assert_includes scripts, "face_state"
    assert_includes scripts, "visual_governor"
    assert_operator scripts.index("face_state"), :<, scripts.index("visual_governor")
  end

  def test_face_state_classifies_runtime_status
    source = read("../RAILS/master/public/face_state.js")
    assert_includes source, "dataset.masterState"
    assert_includes source, "MODE_BUSY"
    assert_includes source, "MODE_FAIL"
  end

  # The governor reads its limits from the face contract's spatial budget and keeps
  # 24 fps and 200 particles only as the fallback when the contract is absent.
  def test_visual_governor_is_quiet_and_freezes_only_on_explicit_signal
    source = read("../RAILS/master/public/visual_governor.js")

    assert_includes source, "window.MASTER_FACE_CONTRACT"
    assert_includes source, "Number(BUDGET.active_fps) || 24"
    # let, not const: the reduced-motion and battery clamps below reassign them.
    assert_includes source, "let maxFps = idle ? idleFps : activeFps"
    assert_match(/let maxParticles = .*\(mobile \? 120 : 200\)/, source)
    assert_includes source, "freezeOnFail: false"
    assert_includes source, "dataset.visualRuntime === \"frozen\""
  end
end
