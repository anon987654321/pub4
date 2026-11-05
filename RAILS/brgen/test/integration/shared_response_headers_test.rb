# frozen_string_literal: true

require "test_helper"

# Response headers the shared engine sends from every app: the legal pages'
# revalidation, Cross-Origin-Resource-Policy and the named CSP hosts.
class SharedResponseHeadersTest < ActionDispatch::IntegrationTest
  setup { host! "brgen.no" }

  def policy
    response.headers["Content-Security-Policy-Report-Only"] || response.headers["Content-Security-Policy"]
  end

  def directive(name)
    policy.split(";").map(&:strip).find { _1.start_with?("#{name} ") }.to_s.split.drop(1)
  end

  test "a signed-out reader revalidates a legal page and gets a 304 when nothing changed" do
    # The first visit mints the guest and the session the key names, so the
    # second response is the one a returning reader revalidates.
    get "/privacy"
    get "/privacy"
    assert_response :success

    etag = response.headers["ETag"]
    assert etag.present?, "the legal page sends no ETag"
    cache = response.headers["Cache-Control"]
    assert_includes cache, "private"
    assert_includes cache, "must-revalidate"
    assert_includes cache, "max-age=0"

    get "/privacy", headers: { "If-None-Match" => etag }
    assert_response :not_modified

    get "/terms", headers: { "If-None-Match" => etag }
    assert_response :success, "another page answered with the privacy page's ETag"
  end

  test "the legal page's ETag changes with the language" do
    get "/privacy"
    etag = response.headers["ETag"]

    host! "lsangeles.com"
    get "/privacy", headers: { "If-None-Match" => etag }
    assert_response :success
  end

  test "a signed-in reader's legal page is always rendered" do
    user = User.strict_loading(false).create!(email_address: "legal_reader@brgen.no", password: "password123",
                                              username: "legal_reader", guest: false)
    post session_path, params: { email_address: user.email_address, password: "password123" }

    get "/privacy"
    assert_response :success
    etag = response.headers["ETag"]
    get "/privacy", headers: { "If-None-Match" => etag }
    assert_response :success
  end

  test "pages say same-origin and images say cross-origin" do
    get "/privacy"
    assert_equal "same-origin", response.headers["Cross-Origin-Resource-Policy"]

    blob = ActiveStorage::Blob.create_and_upload!(io: file_fixture("tiny.png").open, filename: "tiny.png",
                                                  content_type: "image/png")
    get rails_blob_path(blob, disposition: "inline")
    assert_equal "cross-origin", response.headers["Cross-Origin-Resource-Policy"]
    follow_redirect!
    assert_response :success
    assert_equal "image/png", response.media_type
    assert_equal "cross-origin", response.headers["Cross-Origin-Resource-Policy"]
  end

  test "Permissions-Policy declines browsing topics" do
    get "/privacy"
    assert_includes response.headers["Permissions-Policy"], "browsing-topics=()"
  end

  test "the policy names its style, connect and frame hosts instead of every https host" do
    get "/privacy"

    %w[style-src connect-src frame-src].each do |name|
      refute_includes directive(name), "https:", "#{name} admits every HTTPS host"
    end
    assert_includes directive("style-src"), "https://cdn.jsdelivr.net"
    assert_includes directive("connect-src"), "https://tiles.openfreemap.org"
    frames = directive("frame-src")
    Shared::LinkEmbed::PROVIDERS.each do |provider|
      host = URI(provider.player_url("x/y")).then { "#{_1.scheme}://#{_1.host}" }
      assert_includes frames, host, "#{provider.label}'s player would be blocked"
    end
    assert_includes frames, "https://www.youtube.com"
    assert_includes frames, Rails.application.config.x.master_web_url
  end
end
