# frozen_string_literal: true

require "test_helper"

# The three PWA routes, asked for over HTTP.
#
# `pwa_master_contract_test` greps the ERB and `pwa_offline_test` covers the
# offline page, so what the manifest and the service worker actually serve was
# unmeasured: their content types, and whether the worker survives a render
# failure. Both are load-bearing and neither is visible in a template.
#
# A manifest served as text/html installs nothing, and a service worker served
# as anything but JavaScript is refused by the browser with a console error a
# deploy never sees.
class PwaServingTest < ActionDispatch::IntegrationTest
  test "the manifest is served as a manifest" do
    get pwa_manifest_path(format: :json)

    assert_response :success
    assert_equal "application/manifest+json", response.media_type

    manifest = JSON.parse(response.body)
    assert_equal "Amber", manifest["name"], "the app name comes from pwa_app_name"
    refute_empty manifest["icons"], "an installable manifest needs an icon"
    assert_includes %w[standalone fullscreen minimal-ui], manifest["display"]
  end

  test "the service worker is served as javascript" do
    get pwa_service_worker_path

    assert_response :success
    assert_equal "application/javascript", response.media_type
    assert_includes response.body, "self.addEventListener",
                    "a worker that registers no listener is not a worker"
  end

  # The concern rescues a render failure and answers with a minimal worker
  # rather than an error page, because a 500 here leaves whatever is already
  # installed in place with no way to replace it. That fallback is the half a
  # template grep cannot see.
  test "a worker that fails to render is still a valid worker" do
    get pwa_service_worker_path
    assert_response :success

    source = File.read(Rails.root.join("../shared/app/controllers/concerns/shared/pwa_serving.rb"))
    assert_includes source, "self.skipWaiting()",
                    "the rescue path must still install; see the comment beside it"
    assert_includes source, "application/javascript",
                    "the rescue path must keep the content type, or the browser refuses it"
  end

  test "the offline page renders without a session" do
    get pwa_offline_path

    assert_response :success
  end
end
