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
    assert_match(/aside class="sidebar"[\s\S]*?#{Regexp.escape(Rails.application.config.x.master_web_url)}/, response.body)
    assert_includes response.body, 'aria-label="AI assistant"'
  end

  def test_root_feed_tabs_are_wired
    host! "brgen.no"
    get root_url
    assert_response :success
    # link_to renders class before href, so match loosely rather than
    # requiring the class attribute to sit immediately before the tab text.
    assert_match(/class="feed-tab active"[^>]*>For you</, response.body)
    assert_includes response.body, ">Following</"
    assert_includes response.body, 'feed=following'
    get root_url(feed: "following")
    assert_response :success
    assert_match(/class="feed-tab active"[^>]*>Following</, response.body)
  end

  def test_guest_root_can_open_master_embed
    host! "brgen.no"
    get root_url(master: 1)
    assert_response :success
    assert_includes response.body, 'class="master-embed-frame"'
    assert_includes response.body, Rails.application.config.x.master_web_url
  end
end
