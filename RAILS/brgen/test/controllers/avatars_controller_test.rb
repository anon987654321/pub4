# frozen_string_literal: true

require "test_helper"

class AvatarsControllerTest < ActionDispatch::IntegrationTest
  # brgen answers only its own domains; a bare request is a 404 before routing.
  setup { host! "brgen.no" }

  test "numeric IDs render deterministic identicons without exposing account existence" do
    identifier = (User.unscoped.maximum(:id).to_i + 1_000).to_s

    get "/users/#{identifier}/avatar"

    assert_response :success
    assert_equal "image/svg+xml", response.media_type
    expected = Quilt::Identicon.new(identifier, scale: 6, transparent: true, format: "svg").to_blob
    assert_equal expected, response.body
  end
end
