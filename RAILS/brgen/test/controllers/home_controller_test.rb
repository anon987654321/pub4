# frozen_string_literal: true

require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  def test_guest_root_shows_social_feed
    host! "brgen.no"
    get root_url
    assert_response :success
    assert_includes response.body, "compose-box"
    assert_includes response.body, "feed-panel"
    assert_not_includes response.body, 'class="master-embed-frame"'
  end

  def test_guest_root_can_open_master_embed
    host! "brgen.no"
    get root_url(master: 1)
    assert_response :success
    assert_includes response.body, 'class="master-embed-frame"'
    assert_includes response.body, Rails.application.config.x.master_web_url
  end
end