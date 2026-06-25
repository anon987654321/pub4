# frozen_string_literal: true

require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  def test_guest_root_embeds_master
    get root_url
    assert_response :success
    assert_includes response.body, 'class="master-embed-frame"'
    assert_includes response.body, Rails.application.config.x.master_web_url
    assert_not_includes response.body, "Welcome to Amber"
  end
end