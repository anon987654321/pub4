# frozen_string_literal: true

require "json"
require "minitest/autorun"

class PwaMasterContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def read(relative)
    File.read(File.join(ROOT, relative))
  end

  def test_master_manifest_is_installable
    manifest = read("app/views/pwa/manifest.json.erb")
    assert_includes manifest, '"start_url": "/"'
    assert_includes manifest, '"display": "standalone"'
    assert_includes manifest, "theme_color"
    assert_includes manifest, "background_color"
  end

  def test_master_service_worker_avoids_stale_face_precache
    sw = read("public/sw.js")
    assert_match(/Never cache digested/, sw)
    assert_match(/\/assets\//, sw)
    refute_includes sw, "/face.js'"
  end

  def test_chat_shell_links_manifest_and_viseme_assets
    index = read("app/views/chat/index.html.erb")
    assert_match(/pwa_manifest_path/, index)
    assert_includes index, "visemePacks"
    assert_includes index, "clusterMiner"
  end
end