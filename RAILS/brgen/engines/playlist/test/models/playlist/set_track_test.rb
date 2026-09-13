# frozen_string_literal: true

require "test_helper"

class Playlist::SetTrackTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @user = User.strict_loading(false).create!(email_address: "set_track@brgen.no",
                                               password: "password123", city: @city)
    @set = Playlist::Set.create!(user: @user, name: "Spor")
    @track = Playlist::Track.create!(title: "Én gang", user: @user)
  end

  test "a track sits in a set once" do
    Playlist::SetTrack.create!(set: @set, track: @track, user: @user, position: 1)
    again = Playlist::SetTrack.new(set: @set, track: @track, user: @user, position: 2)

    assert_not again.valid?
    assert again.errors.added?(:playlist_set_id, :taken, value: @set.id)
  end

  test "a set's tracks read in position order whatever order they were added" do
    last = Playlist::SetTrack.create!(set: @set, track: @track, user: @user, position: 3)
    earlier = Playlist::Track.create!(title: "Før", user: @user)
    first = Playlist::SetTrack.create!(set: @set, track: earlier, user: @user, position: 1)

    assert_equal [ first.id, last.id ], Playlist::Set.find(@set.id).set_tracks.ids
  end
end
