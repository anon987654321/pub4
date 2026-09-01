# frozen_string_literal: true

require "minitest/autorun"
require_relative "face_manifest_helper"

class VisualGovernorSpec < Minitest::Test
  include FaceManifestHelper

  ROOT = File.expand_path("../..", __dir__)
  GOVERNOR = File.join(ROOT, "web", "public", "visual_governor.js")
  # layouts/application.html.erb is dead for this purpose — ChatController#index
  # renders `layout: false` (web/CLAUDE.md); chat/index.html.erb is the real page.
  ENTRYPOINT = File.join(ROOT, "web", "app", "views", "chat", "index.html.erb")

  def test_visual_governor_caps_fps_and_particles
    source = File.read(GOVERNOR)
    # let, not const: the reduced-motion and battery clamps below reassign it.
    assert_includes source, "let maxFps = 24"
    assert_includes source, "let maxParticles = 200"
    assert_includes source, "window.MASTER_VISUAL_LIMITS"
  end

  def test_visual_governor_pauses_hidden_tabs
    source = File.read(GOVERNOR)
    assert_includes source, "document.hidden"
    assert_includes source, "visibilitychange"
    assert_includes source, "hiddenWaiters"
  end

  # mask.js was superseded by face.js and is no longer referenced anywhere in
  # the live page — the invariant that matters now is that visual_governor
  # (which patches window.requestAnimationFrame) is in the deferred boot
  # manifest, which always finishes executing before face.js's dynamic
  # import() can fire (that import lives inside loadFace(), only called from
  # the primer tap handler — no user tap is possible before deferred scripts
  # have already run), and that face.js is never eagerly <script>-tagged.
  def test_entrypoint_loads_visual_governor_in_deferred_manifest_before_any_tap
    source = File.read(ENTRYPOINT)
    assert_includes shell_manifest, "visual_governor"
    refute_match(/<script[^>]+src=["'][^"']*face\.js/, source)
    assert_includes source, 'import("<%= asset_path("face.js") %>")'
  end
end
