# frozen_string_literal: true

require "application_system_test_case"

# The infinite-scroll sentinel set data-loading="true" before its reflex and
# only the reflex's reply set it back, so a page that never arrived stopped the
# feed for good, with "Laster mer…" in the status line.
class InfiniteScrollRecoveryTest < ApplicationSystemTestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists? && !City.exists?(domain: "brgen.no")
    city = City.find_by!(domain: "brgen.no")

    owner = User.strict_loading(false).create!(
      email_address: "scroll-#{SecureRandom.hex(4)}@brgen.no", password: "password123", city:,
      username: "scroll_#{SecureRandom.hex(3)}", guest: false
    )
    @club = ActsAsTenant.with_tenant(city) do
      club = Community.create!(name: "Lag #{SecureRandom.hex(3)}", user: owner, privacy: "public")
      club.community_memberships.create!(user: owner, role: "owner")
      26.times { |n| Post.create!(user: owner, city:, community: club, title: "Innlegg #{n}", content: "Tekst") }
      club
    end
  end

  test "a page that never arrives clears the loading state and offers the button again" do
    visit community_path(@club)
    decline_optional_cookies if has_css?("#cookie-consent-banner", wait: 3)
    find("button.welcome-onboarding-close", wait: 5).click if has_css?("button.welcome-onboarding-close", wait: 3)

    # A reflex the server does not know: nothing comes back.
    sentinel = find("#community-posts-sentinel")
    page.execute_script("arguments[0].dataset.infiniteScrollReflexValue = arguments[1]",
                        sentinel, "MissingReflex#load_more")
    within("#community-posts-sentinel") { click_button I18n.t("status.load_more") }

    assert_selector "#community-posts-sentinel [role=status]", text: I18n.t("status.load_more_failed"), wait: 25
    assert_selector "#community-posts-sentinel[data-loading='false']"
    assert_selector "#community-posts-sentinel button", text: I18n.t("status.load_more")
  end
end
