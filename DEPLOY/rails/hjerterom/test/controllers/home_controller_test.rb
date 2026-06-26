# frozen_string_literal: true

require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  def test_root_renders_home
    get root_url
    assert_response :success
  end
end