# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

class TestDillaAudiovisual < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  DILLA = File.join(ROOT, "STUDIO", "dilla")
  VIDEO_RECIPE = File.join(ROOT, "STUDIO", "postpro", "video.yml")

  def test_shared_postpro_video_recipe_has_a_bleeding_edge_default
    data = YAML.safe_load_file(VIDEO_RECIPE, aliases: false)
    assert_includes data.fetch("presets").keys, "dmt_bled"
    filters = data.fetch("presets").fetch("dmt_bled").fetch("filters")
    assert_operator filters.length, :>=, 8
    assert filters.any? { |f| f.start_with?("rgbashift=") }
    assert filters.any? { |f| f.start_with?("tmix=") }
  end

  def test_recorded_video_and_live_visuals_use_the_same_local_three_bundle
    video = File.read(File.join(DILLA, "lib", "radio_video.rb"))
    live = File.read(File.join(DILLA, "lib", "live_audiovisual.rb"))
    assert_includes video, "POSTPRO_VIDEO_RECIPE"
    assert_includes video, "postpro_video!"
    assert_includes video, "DILLA_VIDEO_POSTPRO"
    assert_includes video, "parametricField"
    assert_includes video, "tension"
    assert_includes video, "release"
    assert_includes live, "THREE_MODULE"
    assert_includes live, "DMT"
    assert_includes live, "/state"
    refute_includes live, "three.js.org"
  end
end
