# frozen_string_literal: true

require "test_helper"
require "turbo/broadcastable/test_helper"

# What the listening party page and its broadcasts give the guest's player.
class ListeningPartySyncTest < ActionDispatch::IntegrationTest
  include Turbo::Broadcastable::TestHelper

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    handle = "lps_#{SecureRandom.hex(3)}"
    @host = User.strict_loading(false).create!(email_address: "#{handle}@brgen.no", password: "password123",
                                               username: handle, guest: false, city: @city)

    @set = Playlist::Set.create!(name: "Sett #{SecureRandom.hex(3)}", user: @host, privacy: "public")
    @track = Playlist::Track.new(title: "Regn", artist: "Bergen", user: @host, privacy: "public")
    @track.audio_file.attach(io: StringIO.new("RIFFfake"), filename: "regn.wav", content_type: "audio/wav")
    @track.save!

    @set.add_track!(@track, user: @host)
    @party = @set.create_listening_party!(host: @host, status: "active", current_track: @track)
  end

  teardown { ActsAsTenant.current_tenant = nil }

  test "the party page gives the guest an audio element and the track's source" do
    sign_in_as(@host)

    get playlist.set_listening_party_path(@set)

    assert_response :success
    assert_select "[data-controller=party-audio] audio[data-party-audio-target=audio]"
    sync = css_select("#listening_party_sync[data-party-audio-target=sync]").first
    assert sync, "the sync element is missing"
    assert_includes sync["data-src"], "regn.wav"
    assert_equal @track.id.to_s, sync["data-track-id"]
  end

  # The broadcast replaces #listening_party_sync. The id lived outside the
  # partial, so the first replace removed it and every later one missed.
  test "every sync broadcast carries the element it replaces" do
    2.times do |i|
      broadcasts = capture_turbo_stream_broadcasts(@party.stream_name) do
        @party.sync!(track: @track, position_seconds: 10 * i)
      end
      stream = broadcasts.first
      assert_equal "replace", stream["action"]
      assert_includes stream.to_html, %(id="listening_party_sync")
      assert_includes stream.to_html, %(data-position="#{10 * i}")
    end
  end

  test "the host reports a pause, which guests hear as stopped" do
    sign_in_as(@host)

    broadcasts = capture_turbo_stream_broadcasts(@party.stream_name) do
      patch playlist.set_listening_party_path(@set), params: { position_seconds: 42, playing: "false" }
    end

    assert_response :ok
    assert_equal 42, @party.reload.position_seconds
    assert_includes broadcasts.first.to_html, %(data-playing="false")
  end

  private

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
    host! "radio.brgen.no"
  end
end
