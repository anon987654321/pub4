# frozen_string_literal: true

require "application_system_test_case"

class PublicNavigationTest < ApplicationSystemTestCase
  test "ports search and primary navigation render without JavaScript errors" do
    visit root_path

    # Through the keys, in whichever language the app negotiated for this
    # browser. bsdports defaults to :nb, so the English literals here asserted
    # copy the page never renders — "OpenBSD ports" against "OpenBSD-porter".
    locale = find("html", visible: :all)[:lang]
    assert_selector "h1", text: I18n.t("pages.ports", locale: locale)
    # Capybara has no `?` substitution — that is Rails' assert_select.
    assert_selector "[role='search'][aria-label='#{I18n.t("ports.search_label", locale: locale)}']"
    assert_selector "input[aria-label='Search query']"
    # The skip link is off-screen until focused, and Selenium reports "" for a
    # hidden node's text — read textContent rather than filtering on a string
    # the driver can never see.
    skip_link = find("a.skip-link[href='#main-content']", visible: :all)
    assert_equal I18n.t("skip_to_content", locale: locale), skip_link.text(:all).strip
    assert_selector "main#main-content"
    # The nav this used to describe does not exist: its aria-label is
    # t("nav.home"), its links are the three sections, and none of them is
    # current on the home page — so `a[aria-current='page']` could never match
    # here. The assertion was unreachable behind the failing h1 above, so
    # nothing ever said so.
    nav = find("nav[aria-label='#{I18n.t("nav.home", locale: locale)}']")
    assert nav.has_link?(I18n.t("nav.ports", locale: locale))
    assert_no_selector "meta[name='turbo-cache-control'][content='no-cache']", visible: :all
  end

  test "the current section is marked in the primary nav" do
    visit ports_path

    locale = find("html", visible: :all)[:lang]
    assert_selector "nav[aria-label='#{I18n.t("nav.home", locale: locale)}'] a[aria-current='page']",
                    text: I18n.t("nav.ports", locale: locale)
  end
end
