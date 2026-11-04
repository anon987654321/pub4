# frozen_string_literal: true

require "test_helper"

class SecurityHeadersTest < ActionDispatch::IntegrationTest
  test "pages isolate their browsing context and refuse the camera" do
    get root_path

    assert_equal "same-origin", response.headers["Cross-Origin-Opener-Policy"]
    assert_includes response.headers["Permissions-Policy"].to_s, "camera=()"
  end
end
