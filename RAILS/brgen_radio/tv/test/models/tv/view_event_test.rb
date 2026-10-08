# frozen_string_literal: true

require "test_helper"

# tv_view_events has carried watch_time_seconds and completed since the table
# was created. videos#show wrote a row with neither, so the table recorded that
# a signed-in user opened a page and nothing about whether they watched it —
# and Tv::Video.trending sorted views_count, which is incremented on that same
# page load. These pin the signal, its clamp, and the ranking that reads it.
class Tv::ViewEventTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @owner = User.strict_loading(false).create!(
      email_address: "tv_watcher_owner@brgen.no", password: "password123", city: @city
    )
    @viewer = User.strict_loading(false).create!(
      email_address: "tv_watcher@brgen.no", password: "password123", city: @city
    )
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def channel
    @channel ||= Tv::Channel.create!(
      user: @owner, name: "Watch Time", slug: "watch-time-#{SecureRandom.hex(4)}"
    )
  end

  def video(title:, duration: 100)
    Tv::Video.create!(
      channel: channel, user: @owner, title: title, status: "published",
      published_at: Time.current, duration_seconds: duration
    )
  end

  test "progress records watch time and is not marked complete part-way" do
    ActsAsTenant.with_tenant(@city) do
      event = video(title: "Bybanen part 1").view_events.create!(user: @viewer)

      assert event.record_progress!(40)
      assert_equal 40, event.reload.watch_time_seconds
      refute event.completed
      assert_in_delta 0.4, event.progress_fraction, 0.001
    end
  end

  test "watch time is monotonic, so an out-of-order report cannot erase it" do
    ActsAsTenant.with_tenant(@city) do
      event = video(title: "Bybanen part 2").view_events.create!(user: @viewer)

      event.record_progress!(70)
      # The player reports on pause, on tab hide and on unload; a beacon queued
      # earlier can land later. Taking the max is what keeps 70 from becoming 20.
      event.record_progress!(20)

      assert_equal 70, event.reload.watch_time_seconds
    end
  end

  test "watch time is clamped to the video's own duration" do
    ActsAsTenant.with_tenant(@city) do
      event = video(title: "Bybanen part 3", duration: 60).view_events.create!(user: @viewer)

      # Seconds arrive from the client. Unclamped, the ranking is forgeable by
      # anyone who can post a number.
      event.record_progress!(9_999)

      assert_equal 60, event.reload.watch_time_seconds
      assert event.completed
    end
  end

  test "completion is 90 percent, not the final frame" do
    ActsAsTenant.with_tenant(@city) do
      event = video(title: "Bybanen part 4", duration: 100).view_events.create!(user: @viewer)

      event.record_progress!(89)
      refute event.reload.completed, "89% is short of the threshold"

      event.record_progress!(91)
      assert event.reload.completed, "the last timeupdate rarely reaches duration"
    end
  end

  test "a video with no duration records watch time without claiming completion" do
    ActsAsTenant.with_tenant(@city) do
      event = video(title: "Bybanen live", duration: nil).view_events.create!(user: @viewer)

      assert event.record_progress!(30)
      assert_equal 30, event.reload.watch_time_seconds
      assert_nil event.completed
      assert_nil event.progress_fraction
    end
  end

  test "progress on a freshly-found event does not violate strict loading" do
    ActsAsTenant.with_tenant(@city) do
      created = video(title: "Bybanen strict").view_events.create!(user: @viewer)

      bare = Tv::ViewEvent.find_by(id: created.id)
      refute bare.association(:video).loaded?, "guard: video must NOT be preloaded"

      assert bare.record_progress!(25)
      assert_equal 25, created.reload.watch_time_seconds
    end
  end

  # The ranking is the reason the column matters. Before this, trending sorted
  # views_count — incremented on page load — so a bounce ranked like a full view.
  test "trending ranks watched-through over merely opened" do
    ActsAsTenant.with_tenant(@city) do
      bounced = video(title: "Clickbait", duration: 100)
      watched = video(title: "Actually good", duration: 100)

      # The bait was opened far more often and abandoned immediately.
      bounced.update!(views_count: 500)
      bounced.view_events.create!(user: @viewer).record_progress!(3)

      watched.update!(views_count: 10)
      watched.view_events.create!(user: @viewer).record_progress!(95)

      ranked = Tv::Video.trending.to_a
      assert_equal watched.id, ranked.first.id,
                   "500 page opens must not outrank one viewer who watched it through"
    end
  end

  test "a video with no watch time still ranks, by views" do
    ActsAsTenant.with_tenant(@city) do
      unreported = video(title: "No reports yet")
      unreported.update!(views_count: 7)

      assert_includes Tv::Video.trending.to_a.map(&:id), unreported.id
    end
  end
end
