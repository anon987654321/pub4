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
    # The "Bergen, akkurat nå" intro banner was removed — the page opens straight
    # into the feed. Wayfinding to the verticals now lives in the top nav.
    assert_not_includes response.body, "city-home-intro"
    assert_includes response.body, "nav_swiper"
    # AI is a chip / sidebar link, not an eager above-fold iframe hero.
    assert_not_includes response.body, 'class="ai-embed-frame"'
    assert_not_includes response.body, 'class="master-embed-frame"'
    assert_match(/aside class="sidebar"[\s\S]*?#{Regexp.escape(Rails.application.config.x.master_web_url)}/, response.body)
    # Through the key, not the English. The sidebar link stopped carrying a
    # hardcoded aria-label="AI assistant" when it became link_to
    # t("nav.ai_assistant") — its visible text is its accessible name now — and
    # this assertion went red on a page that was rendering the link correctly,
    # in Norwegian, exactly as intended. brgen renders nb; an English literal in
    # an assertion here is testing the locale, not the markup.
    assert_includes response.body, I18n.t("nav.ai_assistant", locale: :nb)
    assert_includes response.body, "form-submit-blank"
  end

  test "composer submit is not cancelled to replay through requestSubmit" do
    source = File.read(Rails.root.join("app/javascript/controllers/form_submit_controller.js"))
    code = source.gsub(%r{^\s*//.*\n}, "")
    refute_match(/\.requestSubmit\s*\(/, code,
                 "requestSubmit from a cancelled submit is a no-op inside <dialog> — Publiser posted nothing")
  end

  # The verticals stay reachable from root, and reachable exactly once.
  #
  # This asserted a .feed-tab row in the layout's .feed-header. That row listed
  # subapp_nav_items -- the same seven verticals brgen_nav_groups already puts in
  # the always-visible .nav_swiper_bar immediately above it -- so root shipped two
  # sticky horizontal scrollers at top:0 offering the same destinations. The row
  # is gone; the swiper is the primary nav (WIRING_NOTES "Layout"). The count
  # assertion is the part that would have caught the duplicate in the first place.
  def test_root_offers_the_verticals_once
    host! "brgen.no"
    get root_url
    assert_response :success

    %w[markedsplass dating playlist TV takeaway maps messenger].each do |vertical|
      assert_match(/class="nav_link[^"]*"[^>]*>#{Regexp.escape(vertical)}/, response.body,
                   "#{vertical} should be reachable from the nav swiper")
    end

    assert_equal 1, response.body.scan(/class="nav_swiper_bar"/).size
    assert_equal 0, response.body.scan(/class="feed-tabs"/).size,
                 "root must not carry a second nav scroller duplicating the swiper"
  end

  def test_guest_root_can_open_master_embed
    host! "brgen.no"
    get root_url(master: 1)
    assert_response :success
    assert_includes response.body, 'class="master-embed-frame"'
    # Front-page / embed entry must skip the "launch AI" primer.
    assert_includes response.body, "autostart=1"
    assert_includes response.body, "embed=1"
  end

  def test_sign_in_is_chrome_light
    host! "brgen.no"
    get new_session_path
    assert_response :success
    assert_includes response.body, "auth-surface"
    assert_includes response.body, "auth-form-lead"
    assert_match(new_user_path, response.body)
  end
  # sort=latest was implemented in the controller with nothing on the page
  # pointing at it. It is a tab now — for signed-in users only, because guest
  # root carries no feed-tabs by the rule the test above pins.
  def test_the_latest_sort_is_reachable_without_typing_a_query_string
    host! "brgen.no"
    user = User.create!(email_address: "latest-#{SecureRandom.hex(4)}@brgen.no",
                        password: "password12345", username: "lt#{SecureRandom.hex(3)}",
                        city: City.find_by(domain: "brgen.no"))
    post session_url, params: { email_address: user.email_address, password: "password12345" }
    get root_url
    assert_response :success
    assert_includes response.body, root_path(sort: "latest")
  end
end
