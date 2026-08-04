# frozen_string_literal: true

require "application_system_test_case"

class PublicNavigationTest < ApplicationSystemTestCase
  test "home remains usable with Turbo and responsive navigation" do
    visit root_path

    # Through the keys, not the English copy: brgen.no renders in nb, so these
    # became "Hopp til hovedinnhold" and "Hovednavigasjon" when the chrome was
    # localised. What the test is checking is that the skip link and the primary
    # nav are present and labelled, which is locale-independent.
    # visible: :all because the skip link is supposed to be invisible here. It is
    # clipped to 1x1 with clip-path/opacity:0 until :focus (_shell.scss), which is
    # the standard pattern, and Selenium reports "" for the visible text of
    # clipped content -- so the plain `text:` filter asserted something the design
    # guarantees can never be true. Matching on all text still proves what this
    # test is for: the link is present, points at #main-content, and is labelled.
    assert_selector "a.skip-link[href='#main-content']",
                    text: I18n.t("skip_to_content"), visible: :all
    assert_selector "main#main-content"
    assert_selector "nav[aria-label='#{I18n.t("nav.primary_nav")}']"
    assert_no_selector "meta[name='turbo-cache-control'][content='no-cache']", visible: :all

    page.current_window.resize_to(390, 844)
    # Progressive disclosure: tab bar closed by default; peel (+ coach) is the path in.
    assert_selector "button.tab-bar-peel", visible: :all
    assert_selector ".tab-bar-coach", visible: :all
    assert_selector "nav.tab-bar", visible: :all
    assert_selector "nav.tab-bar a[aria-current='page']", visible: :all
  end

  test "home page has no axe-core accessibility violations" do
    visit root_path
    assert_accessible
  end
end
