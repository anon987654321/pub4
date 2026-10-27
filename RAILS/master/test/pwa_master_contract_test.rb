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

    [ index, dashboard ].each do |page|
      assert_match(/pwa_manifest_path/, page)
      assert_match(/theme_color = Master\.tokens\.fetch\("face_root"\)\.fetch\("face_bg"\)/, page)
    end
    # Rendered values are PwaControllerTest's; this pins only where they come from.
    assert_match(/theme_color = Master\.tokens\.fetch\("face_root"\)\.fetch\("face_bg"\)/, manifest)
    assert_match(/"background_color": <%= (?:raw )?theme_color\.to_json %>/, manifest)
    assert_match(/"theme_color": <%= (?:raw )?theme_color\.to_json %>/, manifest)
    manifest_assets = read("config/face_assets.yml")
    assert_includes manifest_assets, "visemePacks"
    assert_includes manifest_assets, "clusterMiner"
  end

  def test_inline_boot_exceptions_are_line_scoped_and_explained
    index = read("app/views/chat/index.html.erb")
    inline_scripts = index.lines.select { |line| line.match?(/^\s*<script nonce=/) }
    assert_equal 5, inline_scripts.size
    assert inline_scripts.all? { |line| line.include?("scan: intentional") }

    inline_styles = index.lines.select { |line| line.match?(/^\s*<style nonce=/) }
    assert_equal 1, inline_styles.size
    assert_includes inline_styles.first, "scan: intentional"

    %w[public/offline.html public/406-unsupported-browser.html].each do |path|
      assert_match(/<style>\/\* scan: intentional/, read(path), "#{path} must document its self-contained style block")
    end
  end

  def test_dashboard_poller_is_external_and_preserves_live_state_contract
    dashboard = read("app/views/dashboard/index.html.erb")
    script = read("public/dashboard_live.js")

    assert_includes dashboard,
'<script src="/dashboard_live.js" nonce="<%= content_security_policy_nonce %>" defer></script>'
    refute_match(/<script\b(?![^>]*\bsrc=)[^>]*>[\s\S]*?fetch\(['"]\/dashboard\/live/m, dashboard)
    assert_includes script, "fetch('/dashboard/live'"
    assert_includes script, "cache: 'no-store'"
    assert_includes script, "document.hidden"
    assert_includes script, "r.status === 401 || r.status === 403"
  end
end
