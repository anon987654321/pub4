# frozen_string_literal: true

require "minitest/autorun"
require_relative "support_face_manifest_helper"

class AttentionModelSpec < Minitest::Test
  include FaceManifestHelper

  ROOT = File.expand_path("..", __dir__)

  def read(path)
    File.read(File.join(ROOT, path))
  end

  def test_attention_model_defines_cognitive_policies
    source = read("../RAILS/master/public/attention_model.js")

    %w[idle thinking listening speaking].each do |mode|
      assert_includes source, "#{mode}:"
    end
    assert_includes source, "eyeCloseTarget"
    assert_includes source, "window.MASTER.attention"
  end

  def test_face_runtime_uses_attention_model
    part2 = read("../RAILS/master/public/face.part2.txt")
    part3 = read("../RAILS/master/public/face.part3.txt")

    assert_includes part2, "MASTER_ATTENTION?.reset"
    assert_includes part3, "MASTER_ATTENTION?.tick"
    assert_includes part3, "_attnEyeClose"
    refute_includes part3, "nextBlink"
  end

  def test_face_js_loads_attention_model_first
    # face.js imports whatever faceModulesList the manifest hands it, so the order lives in face_assets.yml.
    source = read("../RAILS/master/public/face.js")
    assert_includes source, "faceModulesList"
    assert_equal "attention_model.js", face_eager.first
  end
end
