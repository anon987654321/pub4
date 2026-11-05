# frozen_string_literal: true

require "application_system_test_case"

# The quick composer's photo, video and audio inputs are visually hidden behind
# icons, and picking a file gave no sign beyond a tint on the icon, with no way
# to take it off again short of closing the dialog.
class FeedComposeMediaTest < ApplicationSystemTestCase
  test "a chosen photo shows as a thumbnail and can be removed again" do
    visit root_path
    decline_optional_cookies if has_css?("#cookie-consent-banner", wait: 3)
    find("button.welcome-onboarding-close", wait: 5).click if has_css?("button.welcome-onboarding-close", wait: 3)

    find("button.compose-trigger").click
    within("dialog.composer") do
      attach_file "post[image]", file_fixture("tiny.png").to_s, make_visible: true

      assert_selector "ul.compose-media li img[alt='#{I18n.t("compose.media.photo_alt")}']"
      click_button I18n.t("compose.media.remove", name: "tiny.png")

      assert_no_selector "ul.compose-media li"
      assert_equal "", find("input[name='post[image]']", visible: :all).value
    end
  end
end
