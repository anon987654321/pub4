# frozen_string_literal: true

require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  def test_guest_root_shows_social_feed
    host! "brgen.no"
    get root_url
    assert_response :success
    # The resting composer is `.compose-launcher` (a pill that opens a <dialog>)
    # since it stopped growing the feed downward; `.compose-box` is now only the
    # inline live-feed form. A guest still gets it — brgen creates a guest user
    # per browser and PostsController#create allows anonymous posts.
    assert_includes response.body, "compose-launcher"
    assert_includes response.body, "feed-panel"
    assert_includes response.body, "city-home-intro"
    assert_includes response.body, "Bergen, right now"
    # AI is a chip / sidebar link, not an eager above-fold iframe hero.
    assert_not_includes response.body, 'class="ai-embed-frame"'
    assert_not_includes response.body, 'class="master-embed-frame"'
    assert_match(/aside class="sidebar"[\s\S]*?#{Regexp.escape(Rails.application.config.x.master_web_url)}/, response.body)
    assert_includes response.body, 'aria-label="AI assistant"'
  end

  def test_root_feed_tabs_link_to_subapps
    host! "brgen.no"
    get root_url
    assert_response :success
    assert_match(/class="feed-tab"[^>]*>marketplace/, response.body)
    assert_match(/class="feed-tab"[^>]*>dating/, response.body)
    assert_match(/class="feed-tab"[^>]*>playlist/, response.body)
  end

  def test_guest_root_can_open_master_embed
    host! "brgen.no"
    get root_url(master: 1)
    assert_response :success
    assert_includes response.body, 'class="master-embed-frame"'
    assert_includes response.body, Rails.application.config.x.master_web_url
  end

  def test_sign_in_is_chrome_light
    host! "brgen.no"
    get new_session_path
    assert_response :success
    assert_includes response.body, "auth-surface"
    assert_includes response.body, "auth-form-lead"
    assert_match(new_user_path, response.body)
  end
end
