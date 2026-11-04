# frozen_string_literal: true

require "test_helper"

# What the video page's player is given: a poster from the thumbnail, and only
# the metadata until the viewer presses play.
class TvVideoPlayerTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    ActsAsTenant.current_tenant = City.find_by!(domain: "brgen.no")
    @owner = User.strict_loading(false).create!(email_address: "tvp_#{SecureRandom.hex(3)}@brgen.no",
                                                password: "password123", username: "tvp_#{SecureRandom.hex(3)}",
                                                guest: false)
    @channel = Tv::Channel.create!(user: @owner, name: "Spiller-TV", slug: "spiller-#{SecureRandom.hex(4)}")
    @video = Tv::Video.create!(channel: @channel, user: @owner, title: "Fjellet", status: "published",
                               published_at: Time.current, duration_seconds: 30)
    @video.video_file.attach(io: File.open(file_fixture("tiny.mp4")), filename: "tiny.mp4", content_type: "video/mp4")
    host! "tv.brgen.no"
  end

  teardown { ActsAsTenant.current_tenant = nil }

  test "the player loads metadata only and wears the thumbnail's poster variant" do
    @video.thumbnail.attach(io: File.open(file_fixture("tiny.png")), filename: "tiny.png", content_type: "image/png")

    get tv.video_path(@video)

    assert_response :success
    poster = css_select("video[data-tv-player-target=video][preload=metadata]").first&.[]("poster")
    assert poster.present?, "the player has no poster"
    assert_includes poster, "/representations/", "the poster is the full-size thumbnail, not its poster variant"
  end

  test "a video without a thumbnail has no poster" do
    get tv.video_path(@video)

    assert_select "video[preload=metadata]"
    assert_select "video[poster]", 0
  end
end
