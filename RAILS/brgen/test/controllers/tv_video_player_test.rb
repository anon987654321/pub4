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

  VTT = "WEBVTT\n\n00:00.000 --> 00:01.000\nHei\n"

  test "a video with a WebVTT file carries a captions track" do
    @video.captions.attach(io: StringIO.new(VTT), filename: "hei.vtt", content_type: "text/vtt")

    get tv.video_path(@video)

    assert_select "video[preload=metadata] track[kind=captions][srclang=nb][default][label=?]",
                  I18n.t("tv.captions_track")
  end

  test "a video without captions has no track" do
    get tv.video_path(@video)

    assert_select "video track", 0
  end

  test "the upload form takes a captions file and the video keeps it" do
    sign_in_as(@owner)

    get tv.new_channel_video_path(@channel)
    assert_select "input[type=file][name='video[captions]'][accept*=vtt]"

    post tv.channel_videos_path(@channel), params: { video: {
      title: "Med tekst",
      video_file: fixture_file_upload("tiny.mp4", "video/mp4"),
      captions: Rack::Test::UploadedFile.new(StringIO.new(VTT), "text/vtt", original_filename: "tekst.vtt")
    } }

    video = Tv::Video.find_by!(title: "Med tekst")
    assert video.captions.attached?, "the captions file was not kept"
    assert_equal "text/vtt", video.captions.content_type
  end

  test "the player carries the media session's title and channel" do
    get tv.video_path(@video)

    assert_select "[data-controller=tv-player][data-tv-player-title-value=Fjellet][data-tv-player-artist-value=?]",
                  @channel.name
  end

  private

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
    host! "tv.brgen.no"
  end
end
