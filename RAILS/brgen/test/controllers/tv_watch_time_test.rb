# frozen_string_literal: true

require "test_helper"

# The watch-time endpoint takes a number from the client and it feeds
# Tv::Video.trending, so the two things worth pinning are that a viewer can only
# write their own event, and that videos#show hands the player the id to write.
class TvWatchTimeTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @owner = User.strict_loading(false).create!(
      email_address: "wt_owner@brgen.no", password: "password123", username: "wt_owner", guest: false
    )
    @viewer = User.strict_loading(false).create!(
      email_address: "wt_viewer@brgen.no", password: "password123", username: "wt_viewer", guest: false
    )
    @intruder = User.strict_loading(false).create!(
      email_address: "wt_intruder@brgen.no", password: "password123", username: "wt_intruder", guest: false
    )
    ActsAsTenant.current_tenant = @city
    @channel = Tv::Channel.create!(user: @owner, name: "Watch", slug: "watch-#{SecureRandom.hex(4)}")
    @video = Tv::Video.create!(
      channel: @channel, user: @owner, title: "Bybanen i regn", status: "published",
      published_at: Time.current, duration_seconds: 120
    )
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  test "a signed-in viewer's watch time lands on their own event" do
    sign_in_as(@viewer)
    host! "tv.brgen.no"

    event = @video.view_events.create!(user: @viewer)
    patch tv.video_view_event_path(@video, event), params: { watch_time_seconds: 45 }

    assert_response :no_content
    assert_equal 45, event.reload.watch_time_seconds
  end

  test "a viewer cannot write watch time onto someone else's event" do
    event = @video.view_events.create!(user: @viewer)

    sign_in_as(@intruder)
    host! "tv.brgen.no"
    patch tv.video_view_event_path(@video, event), params: { watch_time_seconds: 9_999 }

    # Scoped through Current.user.tv_view_events, so the id simply is not found.
    assert_response :not_found
    assert_nil event.reload.watch_time_seconds
  end

  test "a guest gets no event to report against" do
    host! "tv.brgen.no"
    event = @video.view_events.create!(user: @viewer)

    patch tv.video_view_event_path(@video, event), params: { watch_time_seconds: 30 }

    refute_equal 30, event.reload.watch_time_seconds
  end

  test "videos#show hands a signed-in player the row to report on" do
    sign_in_as(@viewer)
    host! "tv.brgen.no"

    assert_difference -> { Tv::ViewEvent.count }, 1 do
      get tv.video_path(@video)
    end
    assert_response :success

    event = Tv::ViewEvent.order(:id).last
    assert_match tv.video_view_event_path(@video, event), response.body,
                 "the player needs the progress URL or watch time is never reported"
  end
end
