# frozen_string_literal: true

require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "radio_bergen redirects to the playlist radio instead of 404" do
    get "/radio_bergen"

    assert_response :see_other
    assert_equal "https://playlist.brgen.no/", response.headers["Location"]
  end
end
