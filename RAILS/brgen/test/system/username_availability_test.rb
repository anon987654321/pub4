# frozen_string_literal: true

require "application_system_test_case"

# The profile form says whether a typed username is free before saving.
class UsernameAvailabilityTest < ApplicationSystemTestCase
  include CityHostSystemTest

  setup do
    Brgen::CitySeed.sync! if City.table_exists? && !City.exists?(domain: "brgen.no")
    @city = City.find_by!(domain: "brgen.no")
    @me = person("hint_me_#{SecureRandom.hex(2)}")
    @taken = person("hint_taken_#{SecureRandom.hex(2)}")
  end

  test "typing a taken name, then a free one, updates the hint beside the field" do
    sign_in_on_city(@me)
    visit_city(nil, "/users/#{@me.id}/edit")

    fill_in I18n.t("profile.username"), with: @taken.username
    assert_selector "#user_username_hint[data-available=false]",
                    text: I18n.t("profile.username_taken", name: @taken.username)

    free = "hint_free_#{SecureRandom.hex(2)}"
    fill_in I18n.t("profile.username"), with: free
    assert_selector "#user_username_hint[data-available=true]", text: I18n.t("profile.username_available", name: free)
  end

  private

  def person(handle)
    User.strict_loading(false).create!(
      email_address: "#{handle}@brgen.no", password: "password123", username: handle, guest: false, city: @city
    )
  end
end
