# frozen_string_literal: true

require "test_helper"

class Playlist::ListenTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @user = User.strict_loading(false).create!(email_address: "listen@brgen.no", password: "password123", city: @city)
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "a play counts on every playlist holding the track and on no other" do
    ActsAsTenant.with_tenant(@city) do
      track = Playlist::Track.create!(title: "Spilt", user: @user)
      first = Playlist::Playlist.create!(name: "Første liste", user: @user)
      second = Playlist::Playlist.create!(name: "Andre liste", user: @user)
      without = Playlist::Playlist.create!(name: "Uten sporet", user: @user)
      first.add_track!(track, user: @user)
      second.add_track!(track, user: @user)

      2.times { Playlist::Listen.create!(user: @user, track: track) }

      assert_equal [ 2, 2, 0 ], [ first, second, without ].map { |list| list.reload.plays_count }
    end
  end
end
