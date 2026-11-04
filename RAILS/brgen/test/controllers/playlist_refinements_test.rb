# frozen_string_literal: true

require "test_helper"

# Hosted-track writes, listen counting and the player pages: each test names a
# behaviour that was wrong and fails without its fix.
class PlaylistRefinementsTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @owner = member("pr_own")
    @friend = member("pr_friend")
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def member(handle)
    User.strict_loading(false).create!(
      email_address: "#{handle}@brgen.no", password: "password123", username: handle, guest: false, city: @city
    )
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
    host! "radio.brgen.no"
  end

  def upload_audio(name) = Rack::Test::UploadedFile.new(StringIO.new("ID3fake"), "audio/mpeg", original_filename: name)

  def track_for(user, title: "Regnvær", privacy: "public")
    Playlist::Track.create!(title:, artist: "Bergen", user:, source_type: "direct",
                            source_url: "https://example.com/#{SecureRandom.hex(3)}.mp3", privacy:)
  end

  def comment_queries
    count = 0
    counter = ->(*, payload) { count += 1 if payload[:sql].include?("playlist_timestamped_comments") }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end

  test "a bulk upload names the files that did not save" do
    sign_in_as(@owner)

    assert_no_difference -> { Playlist::Track.count } do
      files = [ upload_audio("a.mp3"), upload_audio("b.mp3") ]
      post playlist.hosted_tracks_path, params: { track: { title: "", audio_file: files } }
    end
    assert_redirected_to playlist.hosted_tracks_path
    assert_includes flash[:alert].to_s, "a.mp3"
    assert_includes flash[:alert].to_s, "b.mp3"
  end

  test "a rejected edit leaves the audio file and its history alone" do
    track = Playlist::Track.new(title: "Opptak", artist: "", user: @owner, privacy: "public")
    track.audio_file.attach(io: StringIO.new("ID3fake"), filename: "first.mp3", content_type: "audio/mpeg")
    track.save!
    sign_in_as(@owner)

    assert_no_difference -> { Playlist::AudioVersion.count } do
      patch playlist.hosted_track_path(track), params: { track: { title: "", audio_file: upload_audio("second.mp3") } }
    end
    assert_response :unprocessable_entity
    assert_equal "first.mp3", Playlist::Track.find(track.id).audio_file.filename.to_s
  end

  test "a replay inside the window is not a second play" do
    track = track_for(@owner)
    sign_in_as(@friend)

    assert_difference -> { Playlist::Listen.count }, 1 do
      2.times { post playlist.listens_path, params: { track_id: track.id } }
    end
  end

  test "a private track cannot be play-counted by id" do
    hidden = track_for(@owner, privacy: "private")
    sign_in_as(@friend)

    assert_no_difference -> { Playlist::Listen.count } do
      post playlist.listens_path, params: { track_id: hidden.id }
    end
    assert_response :not_found
  end

  test "a playlist page loads every track's comments in one query" do
    list = Playlist::Playlist.create!(name: "Kveld #{SecureRandom.hex(3)}", user: @owner, public_access: true)
    3.times do |i|
      track = track_for(@owner, title: "Spor #{i}")
      list.add_track!(track, user: @owner)
      Playlist::TimestampedComment.create!(track:, user: @friend, body: "fin", timestamp_seconds: i)
    end
    sign_in_as(@friend)

    queries = comment_queries { get playlist.playlist_path(list) }
    assert_response :success
    assert_equal 1, queries
  end

  test "a playlist page's attachment reads do not grow with its queue" do
    list = Playlist::Playlist.create!(name: "Kveld #{SecureRandom.hex(3)}", user: @owner, public_access: true)
    list.add_track!(track_for(@owner, title: "Først"), user: @owner)
    sign_in_as(@friend)
    attachment_reads = lambda do
      count = 0
      counter = ->(*, payload) { count += 1 if payload[:sql].include?("active_storage_attachments") }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get playlist.playlist_path(list) }
      count
    end

    one = attachment_reads.call
    3.times { |i| list.add_track!(track_for(@owner, title: "Spor #{i}"), user: @owner) }
    assert_equal one, attachment_reads.call
  end

  test "a set page loads every track's comments in one query" do
    set = Playlist::Set.create!(name: "Sett #{SecureRandom.hex(3)}", user: @owner, privacy: "public")
    3.times do |i|
      track = track_for(@owner, title: "Spor #{i}")
      set.add_track!(track, user: @owner)
      Playlist::TimestampedComment.create!(track:, user: @friend, body: "fin", timestamp_seconds: i)
    end
    sign_in_as(@friend)

    queries = comment_queries { get playlist.set_path(set) }
    assert_response :success
    assert_equal 1, queries
  end

  test "the embed takes a bare hex colour and refuses anything else" do
    list = Playlist::Playlist.create!(name: "Kveld #{SecureRandom.hex(3)}", user: @owner, public_access: true)
    host! "radio.brgen.no"

    get playlist.embed_playlist_path(list, color: "ff0000")
    assert_select "[data-playlist-player-color-value=?]", "#ff0000"

    get playlist.embed_playlist_path(list, color: "red;background:url(x)")
    assert_select "[data-playlist-player-color-value=?]", "#00d4ff"
  end

  test "the embed may be framed by any site while the playlist page stays same-origin" do
    list = Playlist::Playlist.create!(name: "Kveld #{SecureRandom.hex(3)}", user: @owner, public_access: true)
    host! "radio.brgen.no"

    get playlist.embed_playlist_path(list)
    assert_nil response.headers["X-Frame-Options"]
    policy = response.headers["Content-Security-Policy-Report-Only"] || response.headers["Content-Security-Policy"]
    assert_includes policy, "frame-ancestors *"

    get playlist.playlist_path(list)
    assert_equal "SAMEORIGIN", response.headers["X-Frame-Options"]
    policy = response.headers["Content-Security-Policy-Report-Only"] || response.headers["Content-Security-Policy"]
    assert_includes policy, "frame-ancestors 'self'"
  end

  test "the hosted track form names sources and privacy in the locale" do
    sign_in_as(@owner)

    get playlist.new_hosted_track_path
    assert_select "select[name='track[source_type]'] option[value=direct]", text: I18n.t("playlist.source_types.direct")
    assert_select "select[name='track[privacy]'] option[value=unlisted]", text: I18n.t("playlist.privacy.unlisted")
  end

  test "only the owner is offered edit and delete on a hosted track" do
    track = track_for(@owner)
    sign_in_as(@friend)

    get playlist.hosted_track_path(track)
    assert_response :success
    assert_select "a[href=?]", playlist.edit_hosted_track_path(track), count: 0
  end

  test "the player seeks by button, announces the track and speaks the locale" do
    track = track_for(@owner)
    Playlist::TimestampedComment.create!(track:, user: @friend, body: "fin", timestamp_seconds: 12)
    sign_in_as(@friend)

    get playlist.hosted_track_path(track)
    assert_select "button.playlist-comment[data-time]"
    assert_select ".playlist-now-playing[aria-live=polite]"
    assert_select "[data-playlist-player-pause-label-value=?]", I18n.t("playlist.pause")
  end

  test "the host sees the end button on a listening party" do
    set = Playlist::Set.create!(name: "Sett #{SecureRandom.hex(3)}", user: @owner, privacy: "public")
    set.create_listening_party!(host: @owner, status: "active")
    sign_in_as(@owner)

    get playlist.set_listening_party_path(set)
    assert_response :success
    assert_select "form[action=?]", playlist.set_listening_party_path(set)
  end
end
