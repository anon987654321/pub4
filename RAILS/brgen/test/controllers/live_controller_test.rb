# frozen_string_literal: true

require "test_helper"

class LiveControllerTest < ActionDispatch::IntegrationTest
  setup do
    # The old fallback was `City.first || City.create!(...)` without a currency,
    # but cities.currency is NOT NULL — so whenever this file ran with an empty
    # cities table (which depends on test order) all three tests died on a
    # constraint violation rather than testing anything. CitySeed is the
    # canonical source for the column set, and is what the other suites use.
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    host! "brgen.no"
  end

  test "live index is open without signup" do
    get live_path
    assert_response :success
    assert_match(/Live/, response.body)
    assert_no_match(/Sign in to continue/, response.body)
  end

  test "guest with location can post to live" do
    # Two hits for one guest: the first sighting builds a soft guest without
    # saving it, and the row is written once the browser returns the session
    # cookie (Shared::Authentication). In the product the location itself
    # arrives by POST, which persists the guest before it is stored.
    get live_path
    assert_response :success
    get live_path

    guest = User.where(guest: true).order(created_at: :desc).first
    assert guest.persisted?
    assert guest
    guest.update_columns(latitude: 60.39, longitude: 5.32, location_updated_at: Time.current)

    assert_difference -> { Post.live.count }, 1 do
      post live_path, params: { post: { content: "Free coffee by the fountain right now" } }
    end
    assert_redirected_to live_path(sort: "fresh")

    post_row = Post.live.order(created_at: :desc).first
    assert post_row.anonymous?
    assert post_row.live?
    assert_equal "anon", post_row.author_name
  end

  test "create without location is rejected" do
    get live_path
    post live_path, params: { post: { content: "Should not land" } }
    assert_redirected_to live_path
    follow_redirect!
    assert_includes(flash[:alert].to_s + response.body, I18n.t("flash.location_required_to_post"))
  end
end
