# frozen_string_literal: true

require "minitest/autorun"
require_relative "face_manifest_helper"

class FaceStateSpec < Minitest::Test
  include FaceManifestHelper

  ROOT = File.expand_path("../..", __dir__)

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
    source = read("web/public/face_state.js")
    assert_includes source, "dataset.masterState"
    assert_includes source, "MODE_BUSY"
    assert_includes source, "MODE_FAIL"
  end

  # NOTE: this file's own header comment claims its limits are "sourced from
  # data/ops/visual.yml" — they are not; it's a static asset that never reads
  # that file, and the two sets of numbers currently disagree entirely
  # (YAML: 30/400/96, JS: 24/200/64). That's a real SINGULARITY violation
  # worth fixing deliberately (e.g. render this as .js.erb, or fetch a small
  # JSON config at boot) rather than papering over here — this spec pins the
  # values actually shipping today so drift is visible, not the YAML's.
  def test_visual_governor_is_quiet_and_freezes_only_on_explicit_signal
    source = read("web/public/visual_governor.js")
    # let, not const: the reduced-motion and battery clamps below reassign it.
    assert_includes source, "let maxFps = 24"
    assert_includes source, "let maxParticles = 200"
    assert_includes source, "freezeOnFail: false"
    assert_includes source, "dataset.visualRuntime === \"frozen\""
  end
end
