# frozen_string_literal: true

require "application_system_test_case"

# The dating deck, driven in a browser: the intro gives way to the deck, and the
# like button on a card records the like and takes the card away. Request tests
# cover LikesController; only a browser runs swipe_controller's fetch, and a card
# that animates away while its POST fails looks exactly like a working like.
class DatingSwipeTest < ApplicationSystemTestCase
  include CityHostSystemTest

  setup do
    Brgen::CitySeed.sync! if City.table_exists? && !City.exists?(domain: "brgen.no")
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.with_tenant(@city) do
      @me = person("swipe_me", gender: "man", looking_for: "woman")
      @other = person("swipe_other", gender: "woman", looking_for: "man")
    end
  end

  test "liking the top card records the like and removes the card" do
    sign_in_on_city(@me)
    visit_city("dating", "/")

    assert_selector "section.dating-discover-panel", visible: true, wait: 5

    card = find("article.swipe-card[data-user-id='#{@other.id}']")
    within(card) { find("button.swipe-action--like").click }

    assert_no_selector "article.swipe-card[data-user-id='#{@other.id}']", wait: 5
    assert wait_until { Dating::Like.exists?(liker_id: @me.id, likee_id: @other.id) },
           "the card left the deck and no like was recorded"
  end

  private

  def person(handle, gender:, looking_for:)
    user = User.strict_loading(false).create!(
      email_address: "#{handle}@brgen.no", password: "password123",
      username: handle, guest: false, city: @city
    )
    profile = Dating::Profile.new(user: user, age: 30, bio: "hei", visible: true, gender: gender, looking_for: looking_for)
    profile.photos.attach(io: StringIO.new(ActiveSupport::TestCase::PIXEL_PNG), filename: "#{handle}.png", content_type: "image/png")
    profile.save!
    user
  end
end
