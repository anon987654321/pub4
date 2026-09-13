# frozen_string_literal: true

require "test_helper"

class Playlist::SetTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @user = User.strict_loading(false).create!(email_address: "set_owner@brgen.no",
                                               password: "password123", city: @city)
  end

  test "a set needs a name and a known privacy level" do
    set = Playlist::Set.new(user: @user, name: "", privacy: "secret")

    assert_not set.valid?
    assert set.errors.added?(:name, :blank)
    assert set.errors.added?(:privacy, :inclusion, value: "secret")
  end

  test "visible hides private sets and publicly_listed hides unlisted ones too" do
    shown = Playlist::Set.create!(user: @user, name: "Åpent", privacy: "public")
    unlisted = Playlist::Set.create!(user: @user, name: "Lenke", privacy: "unlisted")
    hidden = Playlist::Set.create!(user: @user, name: "Privat", privacy: "private")
    mine = Playlist::Set.where(user_id: @user.id)

    assert_equal [ shown.id, unlisted.id ].sort, mine.visible.ids.sort
    assert_equal [ shown.id ], mine.publicly_listed.ids
    assert_not_includes mine.visible, hidden
  end

  test "add_track! appends in order and adds the same track once" do
    set = Playlist::Set.create!(user: @user, name: "Rekkefølge")
    first = Playlist::Track.create!(title: "A", user: @user)
    second = Playlist::Track.create!(title: "B", user: @user)

    assert_equal 1, set.add_track!(first, user: @user).position
    assert_equal 2, set.add_track!(second, user: @user).position
    assert_no_difference "Playlist::SetTrack.count" do
      set.add_track!(first, user: @user)
    end
  end

  test "the duration adds up its tracks and shows hours only past an hour" do
    set = Playlist::Set.create!(user: @user, name: "Lengde")
    set.add_track!(Playlist::Track.create!(title: "Kort", user: @user, duration_seconds: 125), user: @user)
    assert_equal "2:05", Playlist::Set.find(set.id).formatted_duration

    set.add_track!(Playlist::Track.create!(title: "Lang", user: @user, duration_seconds: 3_600), user: @user)
    assert_equal 3_725, Playlist::Set.find(set.id).total_duration
    assert_equal "1:02:05", Playlist::Set.find(set.id).formatted_duration
  end
end
