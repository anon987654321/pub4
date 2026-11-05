# frozen_string_literal: true

require "application_system_test_case"

# The video page's player, driven in a browser: a note's time seeks the video,
# "use current time" fills the note form from it, and the lock screen is told
# what is playing. Request tests can only see the markup; the seeking and the
# Media Session live in tv_player_controller.
class TvPlayerTest < ApplicationSystemTestCase
  include CityHostSystemTest

  setup do
    Brgen::CitySeed.sync! if City.table_exists? && !City.exists?(domain: "brgen.no")
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.with_tenant(@city) do
      @owner = User.strict_loading(false).create!(email_address: "tvsys_#{SecureRandom.hex(3)}@brgen.no",
                                                  password: "password123", username: "tvsys_#{SecureRandom.hex(3)}",
                                                  guest: false, city: @city)
      @channel = Tv::Channel.create!(user: @owner, name: "Fjord-TV", slug: "fjord-#{SecureRandom.hex(4)}")
      @video = Tv::Video.create!(channel: @channel, user: @owner, title: "Bølgene", status: "published",
                                 published_at: Time.current, duration_seconds: 1)
      @video.video_file.attach(io: File.open(file_fixture("tiny.mp4")), filename: "tiny.mp4", content_type: "video/mp4")
      Tv::VideoNote.create!(video: @video, user: @owner, body: "Slutten", timestamp: 1)
    end
  end

  # Signed in: the page subscribes to its notes stream, which a guest's cable
  # connection is refused (ApplicationCable::PublicStreams), and the system
  # test waits for every stream source on the page to connect.
  test "the lock screen is told the video and its channel" do
    sign_in_on_city(@owner)
    visit_city("tv", "/videos/#{@video.slug}")

    assert_selector "video[data-tv-player-target=video]"
    read = "(m => m && [ m.title, m.artist ])(navigator.mediaSession.metadata)"
    metadata = wait_until { evaluate_script(read) }
    assert_equal [ "Bølgene", "Fjord-TV" ], metadata
  end

  test "a note's time seeks the player and fills the note form" do
    sign_in_on_city(@owner)
    visit_city("tv", "/videos/#{@video.slug}")
    decline_optional_cookies

    assert wait_until { evaluate_script("document.querySelector('video').readyState >= 1") },
           "the video never loaded its metadata"
    find("button[data-tv-seek-to=\"1\"]").click
    assert wait_until { evaluate_script("document.querySelector('video').currentTime") >= 0.9 },
           "the note's time did not seek the video"

    click_button I18n.t("tv.use_current_time", locale: :nb)
    assert_equal "1", find_field("video_note_timestamp").value
  end
end
