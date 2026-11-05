# frozen_string_literal: true

require "application_system_test_case"

# The welcome dialog's primary button leads somewhere: to the first step, where
# a newcomer picks a neighbourhood and joins communities. Taking it counts as
# having seen the dialog, so it does not greet them again.
class WelcomeFirstStepTest < ApplicationSystemTestCase
  include CityHostSystemTest

  setup do
    Brgen::CitySeed.sync! if City.table_exists? && !City.exists?(domain: "brgen.no")
  end

  test "the primary onboarding button opens the first step and retires the dialog" do
    visit_city(nil, "/")
    decline_optional_cookies if page.has_css?("#cookie-consent-banner", wait: 3)

    within("#welcome-onboarding-brgen", visible: true, wait: 5) do
      click_link I18n.t("onboarding.first_step")
    end

    assert_selector "h1", text: I18n.t("welcome_start.title"), wait: 5
    assert_equal "1", page.evaluate_script("localStorage.getItem('pub4:welcome-onboarding:brgen')")

    visit_city(nil, "/")
    assert_selector "#welcome-onboarding-brgen", visible: :hidden
    assert_no_selector "#welcome-onboarding-brgen", visible: true, wait: 2
  end
end
