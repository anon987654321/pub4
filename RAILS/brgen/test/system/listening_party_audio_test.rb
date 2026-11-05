# frozen_string_literal: true

require "application_system_test_case"

# A listening party's guests hear the host's track in step. The page used to
# show "Now playing ... 42s" and play nothing; party_audio_controller now
# follows the broadcast sync element, and the host's player reports back.
class ListeningPartyAudioTest < ApplicationSystemTestCase
  include CityHostSystemTest

  setup do
    Brgen::CitySeed.sync! if City.table_exists? && !City.exists?(domain: "brgen.no")
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.with_tenant(@city) do
      @host = member("lphost")
      @guest = member("lpguest")

      @set = Playlist::Set.create!(name: "Fredag #{SecureRandom.hex(3)}", user: @host, privacy: "public")
      @track = Playlist::Track.new(title: "Regn", artist: "Bergen", user: @host, privacy: "public")
      @track.audio_file.attach(io: StringIO.new(wav(8)), filename: "regn.wav", content_type: "audio/wav")
      @track.save!
      @set.add_track!(@track, user: @host)
      @party = @set.create_listening_party!(host: @host, status: "active", current_track: @track)
    end
  end

  test "a guest who listens along hears the host's track from the host's position" do
    @party.update!(position_seconds: 3, updated_at: Time.current)
    sign_in_on_city(@guest)
    visit_city("radio", "/sets/#{@set.id}/listening_party?code=#{@party.join_code}")
    decline_optional_cookies

    click_button I18n.t("playlist.party_listen_along", locale: :nb)

    audio = "document.querySelector('[data-party-audio-target=audio]')"
    assert wait_until { evaluate_script("!#{audio}.paused && #{audio}.currentTime >= 3") },
           "the guest's audio is not playing from the host's position"
    assert_includes evaluate_script("#{audio}.src"), "regn.wav"
  end

  test "the host's player reports where it is" do
    sign_in_on_city(@host)
    visit_city("radio", "/sets/#{@set.id}/listening_party")

    audio = "document.querySelector('[data-party-audio-target=audio]')"
    assert wait_until { evaluate_script("#{audio}.readyState >= 1") }, "the host's audio never loaded the current track"
    execute_script("document.querySelector('[data-party-audio-target=audio]').currentTime = 5")

    assert wait_until { @party.reload.position_seconds == 5 }, "the host's seek was not reported to the party"
  end

  private

  def member(handle)
    name = "#{handle}_#{SecureRandom.hex(3)}"
    User.strict_loading(false).create!(email_address: "#{name}@brgen.no", password: "password123",
                                       username: name, guest: false, city: @city)
  end

  # Silence, 8 kHz mono 8-bit: a source every browser decodes without a codec.
  def wav(seconds, rate = 8000)
    data = ("\x80".b * (rate * seconds))
    [ "RIFF", 36 + data.bytesize, "WAVE", "fmt ", 16, 1, 1, rate, rate, 1, 8, "data", data.bytesize ]
      .pack("a4Va4a4VvvVVvva4V") + data
  end
end
