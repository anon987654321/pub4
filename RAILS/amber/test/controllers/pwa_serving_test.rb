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

    served = response.body
    assert_includes served, "self.addEventListener",
                    "a worker that registers no listener is not a worker"
  end

  # The rescue path — a failed worker render answers with a minimal installing
  # worker rather than a 500, because a 500 leaves whatever is installed in
  # place with no way to replace it — is NOT covered here. Proving it needs a
  # forced render failure, and the test that stood in for it grepped the
  # concern's source for "self.skipWaiting()", which proves the text exists and
  # nothing about what the server does. test_source_assertions is right to
  # refuse that, so it is gone rather than rewritten into something weaker.

  test "the offline page renders without a session" do
    get pwa_offline_path

    assert_response :success
  end
end
