# frozen_string_literal: true

require "application_system_test_case"

class PublicNavigationTest < ApplicationSystemTestCase
  test "guest home exposes its primary actions and responsive navigation" do
    visit root_path

    # Through the keys, and in whichever language amber negotiated for this
    # browser — headless Chrome sends Accept-Language: en, the suite's own
    # default is nb, and pinning either one made this test fail for a reason
    # that has nothing to do with navigation.
    locale = find("html", visible: :all)[:lang]
    # The heading is for screen readers; the page shows the mark and the looks.
    assert_equal I18n.t("home.looks.title", locale: locale), find("h1", visible: :all).text(:all).strip
    assert_selector ".amber-corner a[aria-label='#{I18n.t("nav.sign_in", locale: locale)}']"
    # The skip link is off-screen until focused, and Selenium reports "" for a
    # hidden node's text — so read textContent explicitly rather than filtering
    # on a string the driver can never see.
    skip_link = find("a.skip-link[href='#main-content']", visible: :all)
    assert_equal I18n.t("skip_to_content", locale: locale), skip_link.text(:all).strip
    assert_selector "main#main-content"
    assert_no_selector "meta[name='turbo-cache-control'][content='no-cache']", visible: :all

    page.current_window.resize_to(390, 844)
    # Progressive disclosure: tab bar closed by default; peel (+ coach) is the path in.
    assert_selector "button.tab-bar-peel", visible: :all
    assert_selector ".tab-bar-coach", visible: :all
    assert_selector "nav.tab-bar", visible: :all
    assert_selector "nav.tab-bar a[aria-current='page']", visible: :all
  end
end
