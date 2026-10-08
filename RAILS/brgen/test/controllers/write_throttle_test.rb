# frozen_string_literal: true

require "test_helper"

# Shared::WriteThrottle is the floor under every write: a controller with no
# rate_limit of its own still stops a script, and a GET is never counted.
class WriteThrottleTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @user = User.strict_loading(false).create!(
      email_address: "wt_user@brgen.no", password: "password123", username: "wt_user", guest: false
    )
    ActsAsTenant.current_tenant = @city
    @post = Post.create!(user: @user, title: "Bryggen #{SecureRandom.hex(3)}", content: "Noe skjer")
    ActsAsTenant.current_tenant = nil
    host! "brgen.no"
    post session_path, params: { email_address: @user.email_address, password: "password123" }
  end

  def with_limit(controller, limit)
    original = controller.write_throttle_limit
    controller.write_throttle_limit = limit
    yield
  ensure
    controller.write_throttle_limit = original
  end

  test "every ApplicationController write is throttled past the ceiling" do
    with_limit(BookmarksController, 2) do
      2.times { post bookmark_post_path(@post) }
      assert_equal I18n.t("bookmark.saved"), flash[:notice]

      post bookmark_post_path(@post)
      assert_response :redirect
      assert_equal I18n.t("shared.flash.rate_limited"), flash[:alert]
    end
  end

  test "reads are never counted" do
    with_limit(BookmarksController, 1) do
      3.times { get saved_path }
      assert_response :success
      post bookmark_post_path(@post)
      assert_nil flash[:alert]
    end
  end

  test "controllers outside ApplicationSetup answer 429" do
    with_limit(WebVitalsController, 1) do
      post "/web_vitals", params: { lcp: 1200, path: "/" }
      assert_response :no_content
      post "/web_vitals", params: { lcp: 1200, path: "/" }
      assert_response :too_many_requests
    end
  end

  test "the fediverse inbox keeps its own limit and skips the floor" do
    assert_nil Fediverse::InboxesController.write_throttle_limit
  end
end
