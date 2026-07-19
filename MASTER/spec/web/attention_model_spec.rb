# frozen_string_literal: true

require "minitest/autorun"

class AttentionModelSpec < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def read(path)
    File.read(File.join(ROOT, path))
  end

  def test_attention_model_defines_cognitive_policies
    source = read("web/public/attention_model.js")

    %w[idle thinking listening speaking].each do |mode|
      assert_includes source, "#{mode}:"
    end
    assert_includes source, "eyeCloseTarget"
    assert_includes source, "window.MASTER.attention"
  end

  def test_face_runtime_uses_attention_model
    part2 = read("web/public/face.part2.txt")
    part3 = read("web/public/face.part3.txt")

    assert_includes part2, "MASTER_ATTENTION?.reset"
    assert_includes part3, "MASTER_ATTENTION?.tick"
    assert_includes part3, "_attnEyeClose"
    refute_includes part3, "nextBlink"
  end

  def test_face_js_loads_attention_model_first
    source = read("web/public/face.js")
    index = read("web/app/views/chat/index.html.erb")

    assert_includes source, '"attention_model.js"'
    modules = index[/faceModulesList:.*?%w\[([^\]]+)\]/m, 1].to_s.split
    assert_equal "attention_model.js", modules.first
  end
end
