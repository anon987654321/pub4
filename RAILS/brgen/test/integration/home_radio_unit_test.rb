# frozen_string_literal: true

require "test_helper"

# Radio Brgen plays between posts on the front page, through the same player
# facade a post's link gets, built from the radio manifest without asking any
# provider.
class HomeRadioUnitTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @author = User.strict_loading(false).create!(email_address: "radio-feed@brgen.no", password: "password123",
                                                 city: @city)
  end

  teardown { ActsAsTenant.current_tenant = nil }

  test "the fifth place in the feed is a radio track with a player facade" do
    ActsAsTenant.with_tenant(@city) do
      7.times { |n| Post.create!(user: @author, city: @city, title: "Innlegg #{n}", content: "Tekst #{n}") }
    end

    host! "brgen.no"
    get root_path

    assert_response :success
    assert_select "aside.radio-unit h2 a", I18n.t("home.radio_unit.heading", locale: :nb)
    assert_select "aside.radio-unit figure.link-embed button.link-embed-play[data-media-exclusive-src-param]"
  end

  test "the slots are the odd places no sponsored unit uses, and the track turns with the day" do
    assert Brgen::HomeFeed.radio_slot?(5)
    assert Brgen::HomeFeed.radio_slot?(15)
    refute Brgen::HomeFeed.radio_slot?(6)
    refute Brgen::HomeFeed.radio_slot?(4)

    monday = Brgen::HomeFeed.radio_track_for(5, day: Date.new(2026, 11, 2))
    tuesday = Brgen::HomeFeed.radio_track_for(5, day: Date.new(2026, 11, 3))
    assert monday.ok?
    refute_equal monday.source_url, tuesday.source_url
  end
end
