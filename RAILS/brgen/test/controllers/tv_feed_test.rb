# frozen_string_literal: true

require "test_helper"

# The vertical feed only became possible once Tv::ViewEvent recorded watch time.
# Before that, `trending` sorted views_count — incremented on page load — so a
# bounce ranked exactly like a full view, and a feed built on it would have
# served whatever got the most accidental clicks.
class TvFeedTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @owner = User.strict_loading(false).create!(
      email_address: "tf_owner@brgen.no", password: "password123", username: "tf_owner", guest: false
    )
    @viewer = User.strict_loading(false).create!(
      email_address: "tf_viewer@brgen.no", password: "password123", username: "tf_viewer", guest: false
    )
    ActsAsTenant.current_tenant = @city
    @channel = Tv::Channel.create!(user: @owner, name: "Feed", slug: "feed-#{SecureRandom.hex(4)}")
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def video(title:, duration: 60)
    v = Tv::Video.create!(
      channel: @channel, user: @owner, title: title, status: "published",
      published_at: Time.current, duration_seconds: duration
    )
    v.video_file.attach(ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("fake-mp4-bytes"), filename: "clip.mp4",
      content_type: "video/mp4", identify: false
    ))
    v
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  test "the feed renders for a guest and carries a playable source" do
    clip = video(title: "Bybanen i regn")
    host! "tv.brgen.no"

    get tv.feed_path
    assert_response :success
    assert_match clip.title, response.body
    assert_match "tv-feed-item", response.body
  end

  # A vertical feed with nothing to play is a blank screen you cannot scroll
  # past, so a video with no file is not in it at all.
  test "a video with no file is not in the feed" do
    playable = video(title: "Med fil")
    silent = Tv::Video.create!(
      channel: @channel, user: @owner, title: "Uten fil", status: "published", published_at: Time.current
    )
    host! "tv.brgen.no"

    get tv.feed_path
    assert_match playable.title, response.body
    refute_match silent.title, response.body
  end

  test "the feed is ordered by watch time, not by page opens" do
    bounced = video(title: "Klikkagn", duration: 100)
    watched = video(title: "Faktisk bra", duration: 100)

    bounced.update!(views_count: 500)
    bounced.view_events.create!(user: @viewer).record_progress!(3)
    watched.update!(views_count: 5)
    watched.view_events.create!(user: @viewer).record_progress!(95)

    host! "tv.brgen.no"
    get tv.feed_path

    assert_operator response.body.index(watched.title), :<, response.body.index(bounced.title),
                    "500 page opens must not outrank one viewer who watched it through"
  end

  test "the feed creates a view event for a signed-in viewer" do
    clip = video(title: "Sporing")
    sign_in_as(@viewer)
    host! "tv.brgen.no"

    assert_difference -> { Tv::ViewEvent.count }, 1 do
      post tv.video_view_events_path(clip)
    end
    assert_response :success

    body = JSON.parse(response.body)
    event = Tv::ViewEvent.order(:id).last
    assert_equal event.id, body["id"]

    # The id it answers is the one the player then reports progress against.
    patch body["url"], params: { watch_time_seconds: 42 }
    assert_equal 42, event.reload.watch_time_seconds
  end

  # brgen mints a real User row for every cookieless visitor, so a logged-out
  # viewer does record watch time — the same reason they can post and vote. For
  # a video feed that is the point: most viewers are never signed in, and a
  # ranking that only counted accounts would be built on a small minority.
  # Shared::PruneGuestUsersJob destroy_alls those users, and Tv::ViewEvent is
  # dependent: :destroy on them, so the rows go with them rather than orphaning.
  test "a logged-out viewer's watch time counts too" do
    clip = video(title: "Gjest")
    host! "tv.brgen.no"

    assert_difference -> { Tv::ViewEvent.count }, 1 do
      post tv.video_view_events_path(clip)
    end
  end

  test "the next screenful appends rather than replacing" do
    (Tv::FeedController::PAGE + 2).times { |i| video(title: "Klipp #{i}") }
    host! "tv.brgen.no"

    get tv.feed_path
    assert_response :success

    get tv.feed_path(offset: Tv::FeedController::PAGE), as: :turbo_stream
    assert_response :success
    assert_match "turbo-stream", response.body
    assert_match %r{action="append"}, response.body
  end
end
