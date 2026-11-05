# frozen_string_literal: true

require "application_system_test_case"

# The playlist player in a browser. A track whose source cannot be loaded used
# to leave the button saying Pause over silence, because nothing listened for
# the audio element's error or caught play()'s rejection.
class PlaylistPlayerTest < ApplicationSystemTestCase
  include CityHostSystemTest

  setup do
    Brgen::CitySeed.sync! if City.table_exists? && !City.exists?(domain: "brgen.no")
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.with_tenant(@city) do
      @owner = User.strict_loading(false).create!(email_address: "plsys_#{SecureRandom.hex(3)}@brgen.no",
                                                  password: "password123", username: "plsys_#{SecureRandom.hex(3)}",
                                                  guest: false, city: @city)
      @list = Playlist::Playlist.create!(name: "Kveld #{SecureRandom.hex(3)}", user: @owner, public_access: true)
    end
  end

  test "a track that cannot load says so and the button goes back to Play" do
    # The browser refuses port 9 outright, so the source fails at once.
    dead = Playlist::Track.create!(title: "Borte", artist: "Bergen", user: @owner, source_type: "direct",
                                   source_url: "http://127.0.0.1:9/borte.mp3", privacy: "public")
    @list.add_track!(dead, user: @owner)

    visit_city("radio", "/playlists/#{@list.to_param}")
    decline_optional_cookies
    wait_for_player
    find("button.transport-button--primary").click

    assert_selector "p.playlist-player-status[role=status]",
                    text: I18n.t("playlist.status_load_error", locale: :nb), wait: 10
    assert_selector "button.transport-button--primary[aria-pressed=false]"
  end

  test "a playing track keeps playing after a Turbo visit to another radio page" do
    track = Playlist::Track.new(title: "Regn", artist: "Bergen", user: @owner, privacy: "public")
    track.audio_file.attach(io: StringIO.new(wav(30)), filename: "regn.wav", content_type: "audio/wav")
    track.save!
    @list.add_track!(track, user: @owner)

    visit_city("radio", "/playlists/#{@list.to_param}")
    decline_optional_cookies
    wait_for_player
    find("button.transport-button--primary").click
    assert wait_until { evaluate_script("!document.querySelector('audio').paused") }, "the track never started"

    execute_script("Turbo.visit('/sets')")
    assert_current_path "/sets"
    assert_no_selector ".playlist-app"
    docked = "(a => a && !a.paused && a.currentTime > 0)(document.querySelector('#playlist-dock audio'))"
    assert wait_until { evaluate_script(docked) },
           "the track stopped when the page changed"
    assert_selector "#playlist-dock", text: "Regn"
  end

  private

  # The transport bar is in the page before Stimulus connects its controller;
  # a press before then reaches no action.
  def wait_for_player
    connected = "(s => !!(s && s.getControllerForElementAndIdentifier(" \
                "document.querySelector('[data-controller~=playlist-player]'), 'playlist-player')))(window.Stimulus)"
    assert wait_until { evaluate_script(connected) }, "the playlist player never connected"
  end

  # Silence, 8 kHz mono 8-bit: a source every browser decodes without a codec.
  def wav(seconds, rate = 8000)
    data = ("\x80".b * (rate * seconds))
    [ "RIFF", 36 + data.bytesize, "WAVE", "fmt ", 16, 1, 1, rate, rate, 1, 8, "data", data.bytesize ]
      .pack("a4Va4a4VvvVVvva4V") + data
  end
end
