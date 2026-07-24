# frozen_string_literal: true

require "test_helper"

class LiveControllerTest < ActionDispatch::IntegrationTest
  setup do
    @city = City.first || City.create!(name: "Bergen", domain: "brgen.no", slug: "bergen", country_code: "NO", locale: "nb")
    host! "brgen.no"
  end

  test "live index is open without signup" do
    get live_path
    assert_response :success
    assert_match(/Live/, response.body)
    assert_no_match(/Sign in to continue/, response.body)
  end

  test "guest with location can post to live" do
    # Soft guest is created via resume_session on first hit.
    get live_path
    assert_response :success

    guest = User.where(guest: true).order(created_at: :desc).first
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
    assert_match(/Enable location/, flash[:alert].to_s + response.body)
  end
end
