# frozen_string_literal: true

require "test_helper"

# The tv pages and writes that had no request test: shows, episodes, video
# notes, comments and the live-stream pages. Video notes are the reason this
# exists — the controller skipped Tv::BaseController, so find_by_slug_or_id was
# undefined and every note POST raised.
class TvShowsAndNotesTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @owner = User.strict_loading(false).create!(
      email_address: "tsn_owner@brgen.no", password: "password123", username: "tsn_owner", guest: false
    )
    @viewer = User.strict_loading(false).create!(
      email_address: "tsn_viewer@brgen.no", password: "password123", username: "tsn_viewer", guest: false
    )
    ActsAsTenant.current_tenant = @city
    @channel = Tv::Channel.create!(user: @owner, name: "Kanal", slug: "kanal-#{SecureRandom.hex(4)}")
    @video = Tv::Video.create!(
      channel: @channel, user: @owner, title: "Bryggen i tåke", status: "published",
      published_at: Time.current, duration_seconds: 90
    )
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
    host! "tv.brgen.no"
  end

  test "a channel's shows index and a show page render" do
    show = Tv::Show.create!(channel: @channel, title: "Byliv", description: "Om byen", slug: "byliv", published: true)
    Tv::Show.create!(channel: @channel, title: "Kladd", description: "Ikke ute", slug: "kladd", published: false)
    host! "tv.brgen.no"

    get tv.channel_shows_path(@channel)
    assert_response :success
    assert_match show.title, response.body
    refute_match "Kladd", response.body

    get tv.channel_show_path(@channel, show)
    assert_response :success
    assert_match show.title, response.body
  end

  test "an episode renders with its video, and without one it is not a dead end" do
    show = Tv::Show.create!(channel: @channel, title: "Byliv", description: "Om byen", slug: "byliv", published: true)
    Tv::Episode.create!(show:, number: 1, title: "Første", video: @video)
    Tv::Episode.create!(show:, number: 2, title: "Andre")
    host! "tv.brgen.no"

    get tv.episode_channel_show_path(@channel, show, number: 1)
    assert_response :success
    assert_match "Første", response.body

    get tv.episode_channel_show_path(@channel, show, number: 2)
    assert_response :success
    assert_match I18n.t("empty.video_coming_soon"), response.body
  end

  test "a note posts as Current.user, and an empty one is refused rather than a 500" do
    sign_in_as(@viewer)

    assert_difference -> { Tv::VideoNote.count }, 1 do
      post tv.video_video_notes_path(@video), params: { video_note: { body: "Fin overgang", timestamp: 12 } }
    end
    assert_redirected_to tv.video_path(@video)
    note = Tv::VideoNote.order(:id).last
    assert_equal @viewer.id, note.user_id
    assert_equal 12, note.timestamp

    assert_no_difference -> { Tv::VideoNote.count } do
      post tv.video_video_notes_path(@video), params: { video_note: { body: "" } }
    end
    assert_redirected_to tv.video_path(@video)

    post tv.video_video_notes_path(@video), params: { video_note: { body: "" } }, as: :turbo_stream
    assert_response :unprocessable_entity
  end

  test "a comment posts as Current.user" do
    sign_in_as(@viewer)

    assert_difference -> { Tv::Comment.count }, 1 do
      post tv.video_comments_path(@video), params: { tv_comment: { body: "Heia" } }
    end
    assert_redirected_to tv.video_path(@video)
    assert_equal @viewer.id, Tv::Comment.order(:id).last.user_id
  end

  test "the note and comment labels come from the locale" do
    sign_in_as(@viewer)

    get tv.video_path(@video)
    assert_response :success
    assert_match I18n.t("tv.add_note"), response.body
    assert_match I18n.t("tv.note_timestamp"), response.body
    assert_match I18n.t("tv.add_comment"), response.body
  end

  test "a channel names the city it is on, not Bergen" do
    host! "tv.brgen.no"

    get tv.channel_path(@channel)
    assert_response :success
    assert_match I18n.t("tv.channel_subtitle", city: "Bergen"), response.body
  end

  test "the channel search empty state speaks the locale" do
    @video.destroy!
    @channel.destroy!
    host! "tv.brgen.no"

    get tv.channels_path
    assert_response :success
    assert_match CGI.escapeHTML(I18n.t("tv.channels_empty_body")), response.body

    get tv.channels_path(q: "ingenting-her")
    assert_response :success
    assert_match CGI.escapeHTML(I18n.t("tv.no_channels_match")), response.body
  end

  test "the live streams list marks each stream a list item and drops the list when empty" do
    host! "tv.brgen.no"
    get tv.live_streams_path
    assert_response :success
    assert_select "[role=list]", 0

    Tv::LiveStream.create!(user: @owner, channel: @channel, title: "Kveldssending", status: "live")
    get tv.live_streams_path
    assert_select "[role=list] > [role=listitem]", 1
  end

  test "viewer counts pluralise in Norwegian" do
    stream = Tv::LiveStream.create!(user: @owner, channel: @channel, title: "Kveldssending", status: "live", viewer_count: 1)
    host! "tv.brgen.no"

    get tv.live_stream_path(stream)
    assert_response :success
    assert_match I18n.t("tv.live_streams.viewers", count: 1), response.body
    refute_equal I18n.t("tv.live_streams.viewers", count: 1), I18n.t("tv.live_streams.viewers", count: 2)
  end

  test "the new live stream form says streaming is not running" do
    with_live_streaming(true) do
      sign_in_as(@owner)

      get tv.new_channel_live_stream_path(@channel)
      assert_response :success
      assert_match I18n.t("tv.live_streams_unavailable"), response.body
    end
  end

  test "with live streaming off, the owner gets no form and creates no stream" do
    with_live_streaming(false) do
      sign_in_as(@owner)

      get tv.new_channel_live_stream_path(@channel)
      assert_response :not_found
      assert_no_difference -> { Tv::LiveStream.count } do
        post tv.channel_live_streams_path(@channel), params: { live_stream: { title: "Ingen server" } }
      end
      assert_response :not_found
    end
  end

  private

  def with_live_streaming(enabled)
    before = Rails.application.config.x.tv_live_streaming
    Rails.application.config.x.tv_live_streaming = enabled
    yield
  ensure
    Rails.application.config.x.tv_live_streaming = before
  end
end
