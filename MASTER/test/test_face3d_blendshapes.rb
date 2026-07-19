# frozen_string_literal: true

require_relative "test_helper"
require "open3"

class TestFace3dBlendshapes < Minitest::Test
  def test_derive_blend_from_emotion_source_matches_test_mirror
    support = File.read(File.join(Master::ROOT, "web", "public", "face3d_support.js"))
    mirror = File.read(File.join(Master::ROOT, "web", "test", "face3d_blendshape.test.mjs"))
    %w[
      browDown: clamp(e.focus * 0.45
      smile: clamp(Math.max(0, e.valence) * 0.55)
      frown: clamp(Math.max(0, -e.valence) * 0.45)
      cheekRaise: clamp(Math.max(0, e.valence) * 0.30)
    ].each do |needle|
      assert_includes support, needle, "face3d_support.js drifted from blendshape test mirror"
      assert_includes mirror, needle, "blendshape test mirror missing #{needle}"
    end
  end

  def test_face3d_blendshape_node_suite_passes
    skip "node not available" unless system("node", "--version", out: File::NULL, err: File::NULL)

    web_dir = File.join(Master::ROOT, "web")
    out, status = Open3.capture2e("node", "--test", "test/face3d_blendshape.test.mjs", chdir: web_dir)
    assert status.success?, "face3d blendshape tests failed:\n#{out}"
    assert_match(/pass/, out)
  end
end
