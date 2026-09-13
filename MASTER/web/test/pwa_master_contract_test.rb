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

  def test_chat_shell_links_manifest_and_viseme_assets
    index = read("app/views/chat/index.html.erb")
    assert_match(/pwa_manifest_path/, index)
    # visemePacks and clusterMiner are declared in config/face_assets.yml and
    # rendered into MASTER_ASSET_PATHS from there, not spelled in the view.
    manifest = read("config/face_assets.yml")
    assert_includes manifest, "visemePacks"
    assert_includes manifest, "clusterMiner"
  end
end
