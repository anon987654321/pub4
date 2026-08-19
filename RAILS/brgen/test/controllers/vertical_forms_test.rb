# frozen_string_literal: true

require "test_helper"

# Create-forms across the verticals: each of these raised on GET or 400'd on
# POST because a form URL, a namespace or a param scope disagreed with its
# controller. Every one of them is reachable from a link in the UI.
class VerticalFormsTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @owner = User.strict_loading(false).create!(
      email_address: "forms_owner@brgen.no", password: "password123", username: "forms_owner", guest: false
    )
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  test "playlist set form renders and creates under the playlist_set scope" do
    sign_in_as(@owner)
    host! "playlist.brgen.no"

    get playlist.new_set_path
    assert_response :success
    assert_match playlist.sets_path, response.body

    # Posted under the key the rendered form actually uses. This test used to
    # name the key itself (playlist_set), which passed while the form posted
    # set[name] and the controller answered 400 — a test that agrees with the
    # controller about a key the form never sends is not a test of the form.
    scope = response.body[/name="([a-z_]+)\[name\]"/, 1]
    assert_equal "set", scope, "the form's own scope"

    assert_difference -> { Playlist::Set.count }, 1 do
      post playlist.sets_path, params: { scope => { name: "Contract set" } }
    end
    assert_redirected_to playlist.set_path(Playlist::Set.order(:id).last)
  end

  test "playlist sets and hosted tracks indexes resolve their models" do
    host! "playlist.brgen.no"
    # Playlist::Set inside `module Playlist` resolved to Playlist::Playlist::Set.
    get playlist.sets_path
    assert_response :success
    get playlist.hosted_tracks_path
    assert_response :success
  end

  test "tv upload and live stream forms render for the channel owner only" do
    channel = ActsAsTenant.with_tenant(@city) { Tv::Channel.create!(user: @owner, name: "Forms Channel", slug: "forms-channel") }
    sign_in_as(@owner)
    host! "tv.brgen.no"

    get tv.new_channel_video_path(channel)
    assert_response :success
    assert_match tv.channel_videos_path(channel), response.body

    get tv.new_channel_live_stream_path(channel)
    assert_response :success
    stream_scope = response.body[/name="([a-z_]+)\[title\]"/, 1]
    assert_equal "live_stream", stream_scope, "the form's own scope"

    assert_difference -> { Tv::LiveStream.count }, 1 do
      post tv.channel_live_streams_path(channel), params: { stream_scope => { title: "Contract stream" } }
    end

    stranger = User.strict_loading(false).create!(email_address: "stranger@brgen.no", password: "password123", guest: false)
    sign_in_as(stranger)
    host! "tv.brgen.no"
    get tv.new_channel_video_path(channel)
    assert_response :not_found
  end

  test "a tv video comment posts under the tv_comment scope" do
    channel, video = ActsAsTenant.with_tenant(@city) do
      c = Tv::Channel.create!(user: @owner, name: "Comment Channel", slug: "comment-channel")
      [ c, c.videos.create!(user: @owner, title: "Clip", status: "published", published_at: Time.current) ]
    end
    host! "tv.brgen.no"

    get tv.video_path(video) # mints the guest
    assert_response :success
    assert_difference -> { Tv::Comment.count }, 1 do
      post tv.video_comments_path(video), params: { tv_comment: { body: "nice clip" } }
    end
  end

  test "a guest can check in and the page then says so" do
    place = Place.create!(name: "Fløyen", kind: "landmark", latitude: 60.39, longitude: 5.33, city: @city)
    host! "maps.brgen.no"

    get maps.place_path(place)
    assert_response :success
    assert_difference -> { PlaceCheckIn.count }, 1 do
      post maps.check_in_place_path(place), params: { note: "hei" }
    end

    get maps.place_path(place)
    # Through the key, not the English sentence. The view has always said
    # t("maps.checked_in_recently"); this line matched the literal, so it passed
    # only while nb happened to be missing that key and Rails fell back to en.
    assert_match(/#{Regexp.escape(I18n.t("maps.checked_in_recently"))}/, response.body)
  end

  test "reporting a post locates the signed global id" do
    community = Community.create!(slug: "reportable", name: "Reportable", user: @owner, city: @city)
    post_row = Post.create!(user: @owner, community: community, title: "Reportable", content: "hei")
    sign_in_as(@owner)

    assert_difference -> { ModerationReport.count }, 1 do
      post reports_path, params: { target_gid: post_row.to_signed_global_id.to_s, reason: "spam" }
    end
  end

  test "an unlocatable global id is refused instead of raising" do
    sign_in_as(@owner)
    assert_no_difference -> { ModerationReport.count } do
      post reports_path, params: { target_gid: "not-a-signed-gid", reason: "spam" }
    end
    assert_response :redirect
  end
end
