# frozen_string_literal: true

require "test_helper"

class Playlist::PartyMessageTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @host = User.strict_loading(false).create!(email_address: "party_msg@brgen.no",
                                               password: "password123", city: @city)
    set = Playlist::Set.create!(name: "Festsett", user: @host)
    @party = Playlist::ListeningParty.create!(set: set, host: @host, status: "active")
  end

  test "a message needs a body of at most 500 characters" do
    blank = Playlist::PartyMessage.new(listening_party: @party, user: @host, body: "")
    long = Playlist::PartyMessage.new(listening_party: @party, user: @host, body: "x" * 501)

    assert_not blank.valid?
    assert blank.errors.added?(:body, :blank)
    assert_not long.valid?
    assert long.errors.added?(:body, :too_long, count: 500)
  end

  test "chronological reads the conversation in the order it was said" do
    later = say("Neste låt!", at: 1.minute.ago)
    earlier = say("Hei alle", at: 5.minutes.ago)

    assert_equal [ earlier.id, later.id ], Playlist::PartyMessage.where(listening_party_id: @party.id).chronological.ids
  end

  test "a new message is broadcast to the party's stream" do
    assert_broadcasts(@party.stream_name, 1) do
      say("Skru opp")
    end
  end

  private

  def say(body, at: Time.current)
    Playlist::PartyMessage.create!(listening_party: @party, user: @host, body: body, created_at: at)
  end
end
