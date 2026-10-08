# frozen_string_literal: true

require "test_helper"

# A listening party is the one playlist model with real state transitions and a
# generated identifier, which makes it the one where a silent regression costs
# something: a duplicate join_code puts two parties on one link.
class Playlist::ListeningPartyTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @host = User.strict_loading(false).create!(email_address: "party_host@brgen.no",
                                               password: "password123", city: @city)
    @set = ActsAsTenant.with_tenant(@city) do
      Playlist::Set.create!(name: "Fredagssett", user: @host)
    end
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def party(**attrs)
    Playlist::ListeningParty.create!({ set: @set, host: @host, status: "active" }.merge(attrs))
  end

  test "a join code is generated on create" do
    ActsAsTenant.with_tenant(@city) do
      assert_match(/\A[A-Z0-9]{8}\z/, party.join_code)
    end
  end

  test "a supplied join code is kept" do
    ActsAsTenant.with_tenant(@city) do
      assert_equal "LETMEIN1", party(join_code: "LETMEIN1").join_code
    end
  end

  # ensure_join_code is `||=` on create only, so nothing stops two parties being
  # handed the same code by a caller. The uniqueness validation is what does.
  test "join codes are unique" do
    ActsAsTenant.with_tenant(@city) do
      party(join_code: "SHARED01")
      second = Playlist::ListeningParty.new(set: @set, host: @host, status: "active", join_code: "SHARED01")

      assert_not second.valid?
      assert_includes second.errors[:join_code], I18n.t("errors.messages.taken")
    end
  end

  test "end! clears the current track and rewinds" do
    ActsAsTenant.with_tenant(@city) do
      track = Playlist::Track.create!(title: "Siste låt", user: @host)
      live = party(current_track: track, position_seconds: 93)
      live.end!

      assert_equal "ended", live.status
      assert_nil live.current_track
      assert_equal 0, live.position_seconds
      assert_not live.active?
    end
  end

  test "active scope excludes ended parties" do
    ActsAsTenant.with_tenant(@city) do
      live = party
      done = party
      done.end!

      assert_includes Playlist::ListeningParty.active, live
      assert_not_includes Playlist::ListeningParty.active, done
    end
  end

  test "position cannot go negative" do
    ActsAsTenant.with_tenant(@city) do
      assert_not Playlist::ListeningParty.new(set: @set, host: @host, status: "active",
                                              position_seconds: -1).valid?
    end
  end

  test "status is restricted to active and ended" do
    ActsAsTenant.with_tenant(@city) do
      assert_not Playlist::ListeningParty.new(set: @set, host: @host, status: "paused").valid?
    end
  end
end
