# frozen_string_literal: true

require "application_system_test_case"

# html and body never scroll in brgen; .app-shell is the scroller. The radio
# vertical set the shell to overflow: hidden, so on a playlist longer than the
# window the tracks, the queue and the comments below the fold could not be
# reached at all.
class RadioPageScrollTest < ApplicationSystemTestCase
  include CityHostSystemTest

  setup do
    Brgen::CitySeed.sync! if City.table_exists? && !City.exists?(domain: "brgen.no")
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.with_tenant(@city) do
      owner = User.strict_loading(false).create!(email_address: "plscroll_#{SecureRandom.hex(3)}@brgen.no",
                                                 password: "password123", username: "plscroll_#{SecureRandom.hex(3)}",
                                                 guest: false, city: @city)
      @list = Playlist::Playlist.create!(name: "Lang kveld #{SecureRandom.hex(3)}", user: owner, public_access: true)
      40.times do |index|
        track = Playlist::Track.create!(title: "Spor #{index + 1}", artist: "Bergen", user: owner,
                                        source_type: "direct", privacy: "public",
                                        source_url: "http://127.0.0.1:9/spor-#{index}.mp3")
        @list.add_track!(track, user: owner)
      end
    end
  end

  # A wheel, not scrollTop: script can scroll an overflow: hidden box, a person
  # cannot.
  test "the end of a long playlist can be scrolled into view with the wheel" do
    visit_city("radio", "/playlists/#{@list.to_param}")
    decline_optional_cookies
    assert_text :all, "Spor 40"

    # From the middle of the window, over the page rather than the fixed chrome.
    middle = Selenium::WebDriver::WheelActions::ScrollOrigin.viewport(700, 450)
    wheel = page.driver.browser.action
    12.times { wheel.scroll_from(middle, 0, 2000) }
    wheel.perform
    reached = evaluate_script(<<~JS)
      (() => {
        const last = Array.from(document.querySelectorAll("main *"))
          .filter((node) => node.children.length === 0 && node.textContent.trim() === "Spor 40")
          .pop()
        const box = last.getBoundingClientRect()
        return box.bottom <= window.innerHeight && box.top >= 0
      })()
    JS

    assert reached, "the playlist's last track stays below the window however far the page is scrolled"
  end
end
