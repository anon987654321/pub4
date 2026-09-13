# frozen_string_literal: true

require "test_helper"

# The playlist writes that had no request test: collaborations, imports, likes,
# listens, party messages and hosted tracks. One happy path each, plus the
# collaborator block's labels, which rendered the raw role value.
class PlaylistWritesTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @owner = User.strict_loading(false).create!(
      email_address: "pw_own@brgen.no", password: "password123", username: "pw_own", guest: false, city: @city
    )
    @friend = User.strict_loading(false).create!(
      email_address: "pw_friend@brgen.no", password: "password123", username: "pw_friend", guest: false, city: @city
    )
    @playlist = Playlist::Playlist.create!(name: "Kveld #{SecureRandom.hex(3)}", user: @owner, public_access: true)
    @set = Playlist::Set.create!(name: "Sett #{SecureRandom.hex(3)}", user: @owner, privacy: "public")
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
    host! "radio.brgen.no"
  end

  test "the owner adds a collaborator, and the block names the role in the locale" do
    sign_in_as(@owner)

    assert_difference -> { Playlist::Collaboration.count }, 1 do
      post playlist.set_collaborations_path(@set), params: { username: @friend.username, role: "viewer" }
    end
    assert_redirected_to playlist.set_path(@set)
    assert_equal "viewer", Playlist::Collaboration.order(:id).last.role

    get playlist.set_path(@set)
    assert_response :success
    assert_match I18n.t("playlist.roles.viewer"), response.body
    assert_select "select[name=role] option[value=editor]", text: I18n.t("playlist.roles.editor")
  end

  # The set page read @set.tracks and @set.user off a strict-loaded record, so
  # a set page 500'd for everyone.
  test "a set page renders its tracks and sketches in the locale" do
    track = Playlist::Track.create!(title: "Regnvær", artist: "", user: @owner, source_type: "direct",
                                    source_url: "https://example.com/regn.mp3", privacy: "public")
    @set.add_track!(track, user: @owner)
    Playlist::DillaSketch.create!(set: @set, user: @owner, name: "Skisse", state: { pat_: {} }, bars: 8)
    sign_in_as(@owner)

    get playlist.set_path(@set)
    assert_response :success
    assert_match track.title, response.body
    assert_match I18n.t("playlist.bars_count", count: 8), response.body
    assert_match I18n.t("playlist.render_statuses.idle"), response.body
    assert_match I18n.t("playlist.unknown_artist"), response.body
  end

  test "the owner imports links into a playlist" do
    sign_in_as(@owner)

    assert_difference -> { @playlist.playlist_tracks.count }, 2 do
      post playlist.playlist_imports_path(@playlist),
           params: { urls: "https://www.youtube.com/watch?v=abc123\nhttps://soundcloud.com/artist/fin-lat" }
    end
    assert_redirected_to playlist.playlist_path(@playlist)
    assert_equal I18n.t("playlist.imports_queued", count: 2), flash[:notice]
  end

  test "a listener likes a set once" do
    sign_in_as(@friend)

    assert_difference -> { Playlist::Like.count }, 1 do
      2.times { post playlist.set_like_path(@set) }
    end
    assert_redirected_to playlist.set_path(@set)
    assert_equal I18n.t("playlist.set_liked"), flash[:notice]
  end

  test "a listen is recorded and counts a play on the playlists holding the track" do
    track = Playlist::Track.create!(title: "Regnvær", artist: "Bergen", user: @owner, source_type: "direct",
                                    source_url: "https://example.com/regn.mp3", privacy: "public")
    @playlist.add_track!(track, user: @owner)
    sign_in_as(@friend)

    assert_difference -> { Playlist::Listen.count }, 1 do
      post playlist.listens_path, params: { track_id: track.id }
    end
    assert_response :success
    assert_equal 1, @playlist.reload.plays_count.to_i
  end

  test "the party host posts a message" do
    party = @set.create_listening_party!(host: @owner, status: "active")
    sign_in_as(@owner)

    assert_difference -> { party.party_messages.count }, 1 do
      post playlist.set_listening_party_party_messages_path(@set), params: { body: "Skru opp" }
    end
    assert_redirected_to playlist.set_listening_party_path(@set)
  end

  test "a signed-in user uploads a hosted track" do
    sign_in_as(@owner)

    assert_difference -> { Playlist::Track.count }, 1 do
      post playlist.hosted_tracks_path, params: {
        track: {
          title: "Opptak", artist: "", privacy: "public",
          audio_file: Rack::Test::UploadedFile.new(StringIO.new("ID3fake"), "audio/mpeg", original_filename: "opptak.mp3")
        }
      }
    end
    track = Playlist::Track.order(:id).last
    assert_redirected_to playlist.hosted_track_path(track)
    assert_equal @owner.id, track.user_id

    get playlist.hosted_tracks_path
    assert_response :success
    assert_match I18n.t("playlist.unknown_artist"), response.body

    get playlist.edit_hosted_track_path(track)
    assert_response :success
    assert_select "title", text: /#{Regexp.escape(I18n.t("playlist.edit_named", name: track.title))}/
    assert_match CGI.escapeHTML(I18n.t("playlist.replace_audio_file")), response.body
  end

  test "the playlist forms and the radio home render in the locale" do
    sign_in_as(@owner)

    get playlist.new_set_path
    assert_response :success
    assert_match I18n.t("playlist.all_sets"), response.body

    get playlist.new_playlist_path
    assert_response :success
    assert_select "form[aria-label=?]", I18n.t("playlist.new_playlist")

    get playlist.new_hosted_track_path
    assert_response :success
    assert_match CGI.escapeHTML(I18n.t("playlist.audio_files_bulk")), response.body

    get playlist.root_path
    assert_response :success
  end
end
