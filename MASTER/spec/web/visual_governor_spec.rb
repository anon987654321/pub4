# frozen_string_literal: true

require "minitest/autorun"

class VisualGovernorSpec < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  GOVERNOR = File.join(ROOT, "web", "public", "visual_governor.js")
  LAYOUT = File.join(ROOT, "web", "app", "views", "layouts", "application.html.erb")

  def test_visual_governor_caps_fps_and_particles
    source = File.read(GOVERNOR)
    assert_includes source, "const maxFps = 24"
    assert_includes source, "const maxParticles = 200"
    assert_includes source, "window.MASTER_VISUAL_LIMITS"
  end

  def test_visual_governor_pauses_hidden_tabs
    source = File.read(GOVERNOR)
    assert_includes source, "document.hidden"
    assert_includes source, "visibilitychange"
    assert_includes source, "hiddenWaiters"
  end

  def test_layout_loads_visual_governor_before_mask
    layout = File.read(LAYOUT)
    governor_index = layout.index('/visual_governor.js')
    mask_index = layout.index('/mask.js')
    refute_nil governor_index
    refute_nil mask_index
    assert_operator governor_index, :<, mask_index
  end
end
