# frozen_string_literal: true

require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  def test_root_renders_home
    get root_url
    assert_response :success
    assert_includes response.body, "map-home"
    assert_includes response.body, "hjerterom-logo-svg"
    assert_includes response.body, "map-home-dock"
  end
end