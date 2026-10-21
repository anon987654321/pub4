# frozen_string_literal: true

require "minitest/autorun"

class PwaMasterContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def read(relative)
    File.read(File.join(ROOT, relative))
  end

  def test_master_service_worker_avoids_stale_face_precache
    sw = read("public/sw.js")
    assert_match(/Never cache digested/, sw)
    assert_match(/\/assets\//, sw)
    refute_includes sw, "/face.js'"
  end

  def test_chat_and_dashboard_link_the_single_manifest_and_share_theme_token
    index = read("app/views/chat/index.html.erb")
    dashboard = read("app/views/dashboard/index.html.erb")
    manifest = read("app/views/pwa/manifest.json.erb")

    [index, dashboard].each do |page|
      assert_match(/pwa_manifest_path/, page)
      assert_match(/theme_color = Master\.tokens\.fetch\("face_root"\)\.fetch\("face_bg"\)/, page)
    end
    assert_match(/"background_color": <%= theme_color\.to_json %>/, manifest)
    assert_match(/"theme_color": <%= theme_color\.to_json %>/, manifest)
    manifest_assets = read("config/face_assets.yml")
    assert_includes manifest_assets, "visemePacks"
    assert_includes manifest_assets, "clusterMiner"
  end
end
