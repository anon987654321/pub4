# frozen_string_literal: true

require "test_helper"

# engines/playlist had no test directory at all — the only one of the five
# verticals with none, and the second largest by file count. This covers the
# behaviour that is not Rails doing Rails: ordering and idempotence in
# add_track!, and the tenancy of city_trending.
class Playlist::PlaylistTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @other_city = City.find_by!(domain: "oshlo.no")
    @user = User.strict_loading(false).create!(email_address: "pl_owner@brgen.no",
                                               password: "password123", city: @city)
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def track(title)
    Playlist::Track.create!(title: title, user: @user)
  end

  test "add_track! appends in order" do
    ActsAsTenant.with_tenant(@city) do
      list = Playlist::Playlist.create!(name: "Morgenkaffe", user: @user)
      first = list.add_track!(track("A"), user: @user)
      second = list.add_track!(track("B"), user: @user)

      assert_equal 1, first.position
      assert_equal 2, second.position
    end
  end

  # find_or_initialize_by then `return if persisted?` — so a double-add is a
  # no-op rather than a duplicate row, and must not inflate tracks_count either.
  test "add_track! is idempotent for the same track" do
    ActsAsTenant.with_tenant(@city) do
      list = Playlist::Playlist.create!(name: "Kveldstur", user: @user)
      song = track("Same")
      list.add_track!(song, user: @user)

      assert_no_difference -> { list.reload.tracks_count } do
        assert_no_difference "Playlist::PlaylistTrack.count" do
          list.add_track!(song, user: @user)
        end
      end
    end
  end

  # tracks_count starts nil, not 0: playlist_playlists declares tracks_count,
  # likes_count and plays_count as nullable integers with no default. increment!
  # copes — it does `self[attr] ||= 0` first — so this is a trap only for code
  # that reads or orders by the column before the first write, and `popular`
  # orders by plays_count. Asserted as it actually is rather than papered over,
  # so a migration adding the defaults shows up here as a deliberate change.
  test "tracks_count starts nil and reaches 1 on the first add" do
    ActsAsTenant.with_tenant(@city) do
      list = Playlist::Playlist.create!(name: "Ny liste", user: @user)
      assert_nil list.reload.tracks_count

      list.add_track!(track("Only"), user: @user)

      assert_equal 1, list.reload.tracks_count
    end
  end

  test "public_playlists excludes private ones" do
    ActsAsTenant.with_tenant(@city) do
      shown = Playlist::Playlist.create!(name: "Åpen", user: @user, public_access: true)
      hidden = Playlist::Playlist.create!(name: "Privat", user: @user, public_access: false)

      assert_includes Playlist::Playlist.public_playlists, shown
      assert_not_includes Playlist::Playlist.public_playlists, hidden
    end
  end

  # The tv.oshlo.no 500 was one city's rows reaching another city's page, so a
  # city-scoped scope is worth pinning rather than assuming.
  test "city_trending returns only the given city's public playlists" do
    bergen_list = ActsAsTenant.with_tenant(@city) do
      Playlist::Playlist.create!(name: "Bergen topp", user: @user, public_access: true)
    end
    oslo_list = ActsAsTenant.with_tenant(@other_city) do
      Playlist::Playlist.create!(name: "Oslo topp", user: @user, public_access: true)
    end

    ActsAsTenant.without_tenant do
      trending = Playlist::Playlist.city_trending(@city)

      assert_includes trending, bergen_list
      assert_not_includes trending, oslo_list
    end
  end

  test "name is required and capped at 100 characters" do
    ActsAsTenant.with_tenant(@city) do
      assert_not Playlist::Playlist.new(user: @user).valid?
      assert_not Playlist::Playlist.new(name: "x" * 101, user: @user).valid?
      assert Playlist::Playlist.new(name: "x" * 100, user: @user).valid?
    end
  end
end
