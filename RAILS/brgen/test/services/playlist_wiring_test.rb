# frozen_string_literal: true

require "minitest/autorun"
require_relative "../source_reader"

# Playlist, as a wiring contract: what an import writes, what the schema owns,
# who a track belongs to, and what a like reaches.
#
# These four tests were spread through deploy_backlog_test.rb, which bundles
# forty unrelated deploy contracts and had grown past its file-length ceiling
# again. Playlist is one subject and a growing one — ownership, hosted tracks
# and set likes all arrived after the import assertions — so it gets a file
# rather than four more entries in a list of forty.
#
# Reads source as text, like the file it came from: this asserts the wiring
# exists, not that it works.
class PlaylistWiringTest < Minitest::Test
  include SourceReader

  def test_playlist_import_embed_schema_trending_and_expiry_are_wired
    migration = read_source(File.join(ROOT, "brgen/db/migrate/20260707121000_add_playlist_import_embed_and_expiry_fields.rb"))
    playlist = read_source(File.join(ROOT, "brgen/app/models/playlist/playlist.rb"))
    track = read_source(File.join(ROOT, "brgen/app/models/playlist/track.rb"))
    importer = read_source(File.join(ROOT, "brgen/engines/playlist/app/services/playlist/track_import.rb"))
    imports_controller = read_source(File.join(ROOT, "brgen/app/controllers/playlist/imports_controller.rb"))
    playlists_controller = read_source(File.join(ROOT, "brgen/app/controllers/playlist/playlists_controller.rb"))
    tracks_controller = read_source(File.join(ROOT, "brgen/app/controllers/playlist/tracks_controller.rb"))
    routes = read_source(File.join(ROOT, "brgen/config/routes.rb"))
    schema_helper = read_source(File.join(ROOT, "shared/app/helpers/schema_helper.rb"))
    # _player alone. It used to be read together with a _queue partial, on the
    # stated grounds that the player "renders" it — and it did not. _queue was
    # split out of _player, then _player grew the queue markup back inline and
    # nothing rendered the extracted file again. This assertion passed because
    # the file existed, not because the relationship did. Deleted 2026-08-25.
    player = read_source(File.join(ROOT, "brgen/app/views/playlist/playlists/_player.html.erb"))
    show = read_source(File.join(ROOT, "brgen/app/views/playlist/playlists/show.html.erb"))
    index = read_source(File.join(ROOT, "brgen/app/views/playlist/playlists/index.html.erb"))
    hosted_form = read_source(File.join(ROOT, "brgen/app/views/playlist/hosted_tracks/_form.html.erb"))
    stimulus = read_source(File.join(ROOT, "brgen/app/javascript/controllers/playlist_player_controller.js"))

    assert_includes migration, "add_column :playlist_tracks, :expires_at"
    assert_includes migration, "add_column :playlist_tracks, :privacy"
    assert_includes playlist, "city_trending"
    assert_includes playlist, "duration_seconds"
    assert_includes track, "external_embed_url"
    assert_includes track, "youtube_embed_url"
    assert_includes track, "spotify_embed_url"
    assert_includes track, "w.soundcloud.com/player"
    assert_includes importer, "TrackImport"
    assert_includes importer, "youtube.com"
    assert_includes importer, "spotify.com"
    assert_includes importer, "soundcloud.com"
    assert_includes imports_controller, "require_user_session"
    assert_includes imports_controller, "return if performed?"
    assert_includes playlists_controller, "def embed"
    assert_includes playlists_controller, "Playlist::Track.unexpired"
    assert_includes tracks_controller, ":expires_at"
    assert_includes routes, "member { get :embed }"
    assert_includes routes, "resources :imports, only: :create"
    assert_includes schema_helper, "MusicPlaylist"
    assert_includes schema_helper, "MusicRecording"
    assert_includes schema_helper, "iso8601_duration"
    assert_includes player, 'itemtype="https://schema.org/MusicPlaylist"'
    assert_includes player, "data-playlist-player-embed-param"
    assert_includes player, "playlist-embed-frame"
    assert_includes stimulus, "embedTarget"
    assert_includes show, "json_ld_for(@playlist, type: :music_playlist)"
    assert_includes show, "playlist_imports_path"
    assert_includes show, "embed_playlist_url"
    refute_includes show, "embed_playlist_playlist_url"
    assert_includes hosted_form, "form.datetime_field :expires_at"
  end

  def test_playlist_tracks_schema_includes_user_ownership
    schema = read_source(File.join(ROOT, "brgen/db/schema.rb"))
    assert_includes schema, 'create_table "playlist_tracks"'
    assert_includes schema, 't.integer "user_id"', "brgen schema missing playlist_tracks.user_id"
    assert_includes schema, "index_playlist_tracks_on_user_id"
    assert_includes schema, 'add_foreign_key "playlist_tracks", "users"'
  end

  def test_playlist_tracks_and_hosted_tracks_wire_user_ownership
    migration = read_brgen("db/migrate/20260709120100_add_user_to_playlist_tracks.rb")
    track = read_brgen("app/models/playlist/track.rb")
    hosted = read_brgen("app/controllers/playlist/hosted_tracks_controller.rb")
    tracks_controller = read_brgen("app/controllers/playlist/tracks_controller.rb")

    assert_includes migration, "add_reference :playlist_tracks, :user"
    assert_includes track, "belongs_to :user"
    assert_includes hosted, "@track.user = Current.user"
    assert_includes tracks_controller, "user: Current.user"
  end

  def test_playlist_set_likes_controller_and_ui_are_wired
    controller = read_brgen("app/controllers/playlist/likes_controller.rb")
    show = read_brgen("app/views/playlist/sets/show.html.erb")

    assert_includes controller, "class Playlist::LikesController"
    refute_includes controller, "module Playlist"
    assert_includes controller, "find_or_create_by!"
    assert_includes controller, "destroy_all"
    assert_includes show, "set_like_path" # engine-internal helper (unprefixed inside Playlist::Engine)
    assert_includes show, "likes.count"
  end
end
